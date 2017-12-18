require "demiurge/version"
require "demiurge/util"

# Predeclare classes that other required files will use.
module Demiurge
  class StateItem; end
  class Intention < StateItem; end
end

require "demiurge/exception"
require "demiurge/action_item"
require "demiurge/inert_state_item"
require "demiurge/container"
require "demiurge/zone"
require "demiurge/location"
require "demiurge/agent"
require "demiurge/dsl"

require "multi_json"

# Demiurge is a state and simulation library which can be used to
# create games and similar applications.  Its focus is on rich, deep
# simulation with interesting object interactions. To begin using
# Demiurge, see the {Demiurge::Engine} class and/or the
# {file:README.md} file. For more detail, see {file:CONCEPTS.md}.
module Demiurge

  # The Engine class encapsulates one "world" of simulation. This
  # includes state and code for all items, subscriptions to various
  # events and the ability to reload state or code at a later point.
  # It is entirely possible to have multiple Engine objects containing
  # different objects and subscriptions which are unrelated to each
  # other. If Engines share references in common, that sharing is
  # ordinarily a bug. Currently only registered {Demiurge::DSL} Object
  # Types should be shared.
  #
  # @since 0.0.1
  class Engine
    include ::Demiurge::Util # For copyfreeze and deepcopy

    # @return [Integer] The number of ticks that have occurred since the beginning of this Engine's history.
    attr_reader :ticks

    # This is the constructor for a new Engine object. Most frequently
    # this will be called by {Demiurge::DSL} or another external
    # source which will also supply item types and initial state.
    #
    # @param types [Hash] A name/value hash of item types supported by this engine's serialization.
    # @param state [Array] An array of serialized Demiurge items in {Demiurge::StateItem} structured array format.
    # @return [void]
    # @since 0.0.1
    def initialize(types: {}, state: [])
      @klasses = {}
      if types
        types.each do |tname, tval|
          register_type(tname, tval)
        end
      end

      @finished_init = false
      @state_items = {}
      @zones = []
      state_from_structured_array(state || [])

      @item_actions = {}

      @subscriptions_by_tracker = {}

      @queued_notifications = []
      @queued_intentions = []

      nil
    end

    # The "finished_init" callback on Demiurge items exists to allow
    # items to finalize their structure relative to other items. For
    # instance, containers can ensure that their list of contents is
    # identical to the set of items that list the container as their
    # location.  This cannot be done until the container is certain
    # that all items have been added to the engine. The #finished_init
    # engine method calls {Demiurge::StateItem#finished_init} on any
    # items that respond to that callback. Normally
    # {Demiurge::Engine#finished_init} should be called when a new
    # Engine is created, but not when restoring one from a state
    # dump. This method should not be called multiple times, and the
    # Engine will try not to allow multiple calls.
    #
    # @return [void]
    # @since 0.0.1
    def finished_init
      raise("Duplicate finished_init call to engine!") if @finished_init
      @state_items.values.each { |obj| obj.finished_init() if obj.respond_to?(:finished_init) }
      @finished_init = true
    end

    # This method dumps the Engine's state in {Demiurge::StateItem}
    # structured array format.  This method is how one would normally
    # collect a full state dump of the engine suitable for later
    # restoration.
    #
    # @param [Hash] options Options for dumping state
    # @option options [Boolean] copy If true, copy the serialized state rather than allowing any links into StateItem objects. This reduces performance but increases security.
    # @return [Array] The engine's state in {Demiurge::StateItem} structured array format
    # @since 0.0.1
    # @see #load_state_from_dump
    def structured_state(options = { "copy" => false })
      dump = @state_items.values.map { |item| item.get_structure(options) }
      if options["copy"]
        dump = deepcopy(dump)  # Make sure it doesn't share state...
      end
      dump
    end

    # Get a StateItem by its registered unique name.
    #
    # @param name [String] The name registered with the {Demiurge::Engine} for this item
    # @return [StateItem, nil] The StateItem corresponding to this name or nil
    # @since 0.0.1
    def item_by_name(name)
      @state_items[name]
    end

    # Get an Array of StateItems that are top-level {Demiurge::Zone} items.
    #
    # @since 0.0.1
    # @return [Array<Demiurge::StateItem>] All registered StateItems that are treated as {Demiurge::Zone} items
    def zones
      @zones
    end

    # Get an array of all registered names for all items.
    #
    # @return [Array<String>] All registered item names for this {Demiurge::Engine}
    # @since 0.0.1
    def all_item_names
      @state_items.keys
    end

    # Add an intention to the Engine's Intention queue. If this method
    # is called during the Intention phase of a tick, the intention
    # should be excecuted during this tick in standard order. If the
    # method is called outside the Intention phase of a tick, the
    # Intention will normally be executed during the soonest upcoming
    # Intention phase. Queued intentions are subject to approval,
    # cancellation and other normal operations that Intentions undergo
    # before being executed.
    #
    # @param intention [Demiurge::Intention] The intention to be queued
    # @return [void]
    # @since 0.0.1
    def queue_intention(intention)
      @state_items["admin"].state["intention_id"] += 1
      @queued_intentions.push [@state_items["admin"].state["intention_id"], intention]
      nil
    end

    # Queue all Intentions for all registered items for the current tick.
    #
    # @return [void]
    # @since 0.0.1
    def queue_item_intentions()
      next_step_intentions.each { |i| queue_intention(i) }
    end

    # Calculate the intentions for the next round of the Intention
    # phase of a tick.  This is not necessarily the same as all
    # Intentions for the next tick - sometimes an executed
    # {Demiurge::Intention} will queue more {Demiurge::Intention}s to
    # run during the same phase of the same tick.
    #
    # @return [void]
    # @since 0.0.1
    def next_step_intentions()
      @zones.flat_map { |item| item.intentions_for_next_step || [] }
    end

    # Send a warning that something unfortunate but not
    # continuity-threatening has occurred. The problem isn't bad
    # enough to warrant raising an exception, but it's bad enough that
    # we should collect data about the problem. The warning normally
    # indicates a problem in user-supplied code, current state, or the
    # Demiurge gem itself. These warnings can be subscribed to with
    # the notification type "admin_warning".
    #
    # @param message [String] A user-readable log message indicating the problem that occurred
    # @param info [Hash] A hash of additional fields that indicate the nature of the problem being reported
    # @option info [String] "name" The name of the item causing the problem
    # @option info [String] "zone" The name of the zone where the problem is located, if known
    # @return [void]
    # @since 0.0.1
    def admin_warning(message, info = {})
      send_notification({"message" => message, "info" => info}, type: "admin_warning", zone: "admin", location: nil, actor: nil)
    end

    # Send out all pending {Demiurge::Intention}s in the
    # {Demiurge::Intention} queue. This will ordinarily happen at
    # least once per tick in any case. Calling this method outside the
    # Engine's Intention phase of a tick may cause unexpected results.
    #
    # @return [void]
    # @since 0.0.1
    def flush_intentions(options = { })
      state_backup = structured_state("copy" => true)

      infinite_loop_detector = 0
      until @queued_intentions.empty?
        infinite_loop_detector += 1
        if infinite_loop_detector > 20
          raise ::Demiurge::TooManyIntentionLoopsError.new("Over 20 batches of intentions were dispatched in the same call! Error and die!", "final_batch" => @queued_intentions.map { |i| i.class.to_s })
        end

        intentions = @queued_intentions
        @queued_intentions = []
        begin
          intentions.each do |id, a|
            if a.cancelled?
              admin_warning("Trying to apply a cancelled intention of type #{a.class}!", "inspect" => a.inspect)
            else
              a.try_apply(self, id, options)
            end
          end
        rescue RetryableError
          admin_warning("Exception when updating! Throwing away speculative state!", "exception" => $_.jsonable)
          load_state_from_dump(state_backup)
        end
      end

      send_notification({}, type: "tick finished", location: "", zone: "", actor: nil)
      @state_items["admin"].state["ticks"] += 1
      nil
    end

    # Perform all necessary operations and phases for one "tick" of
    # virtual time to pass in the Engine.
    #
    # @return [void]
    # @since 0.0.1
    def advance_one_tick()
      queue_item_intentions
      flush_intentions
      flush_notifications
      nil
    end

    # Get a StateItem type that is registered with this Engine, using the registered name for that type.
    #
    # @param t [String] The registered type name for this class object
    # @return [Class] A StateItem Class object
    # @since 0.0.1
    def get_type(t)
      raise("Not a valid type: #{t.inspect}!") unless @klasses[t]
      @klasses[t]
    end

    # Register a new StateItem type with a name that will be used in structured {Demiurge::StateItem} dumps.
    #
    # @param name [String] The name to use when registering this type
    # @param klass [Class] The StateItem class to register with this name
    # @return [void]
    # @since 0.0.1
    def register_type(name, klass)
      if @klasses[name] && @klasses[name] != klass
        raise "Re-registering name with different type! Name: #{name.inspect} Class: #{klass.inspect} OldClass: #{@klasses[name].inspect}!"
      end
      @klasses[name] ||= klass
      nil
    end

    # StateItems are transient and can be created, recreated or
    # destroyed without warning. They need to be hooked up to the
    # various Ruby code for their actions. The code for actions isn't
    # serialized. Instead, each action is referred to by name, and the
    # engine loads up all the item-name/action-name combinations when
    # it reads the Ruby World Files. This means an action can be
    # referred to by its name when serialized, but the actual code
    # changes any time the world files are reloaded.

    def register_actions_by_item_and_action_name(item_actions)
      item_actions.each do |item_name, act_hash|
        if @item_actions[item_name]
          act_hash.each do |action_name, opts|
            existing = @item_actions[item_name][action_name]
            if existing
              ActionItem::ACTION_LEGAL_KEYS.each do |key|
                if existing[key] && opts[key] && existing[key] != opts[key]
                  raise "Can't register action #{action_name.inspect} for item #{item_name.inspect}, conflict for key #{key.inspect}!"
                end
              end
              existing.merge!(opts)
            else
              @item_actions[item_name][action_name] = opts
            end
          end
        else
          @item_actions[item_name] = act_hash
        end
      end
    end

    def action_for_item(item_name, action_name)
      @item_actions[item_name] ? @item_actions[item_name][action_name] : nil
    end

    def actions_for_item(item_name)
      @item_actions[item_name]
    end

    def instantiate_new_item(name, parent, extra_state = {})
      parent = item_by_name(parent) unless parent.is_a?(StateItem)
      ss = parent.get_structure

      # The new instantiated item is different from the parent because
      # it has its own name, and because it can get named actions from
      # the parent as well as itself. The latter is important because
      # we can't easily make new action procs without an associated
      # World File of some kind.
      ss[1] = name
      ss[2] = deepcopy(ss[2])
      ss[2].merge!(extra_state)
      ss[2]["parent"] = parent.name

      child = register_state_item(StateItem.from_name_type(self, *ss))
      if @finished_init && child.respond_to?(:finished_init)
        child.finished_init
      end
      child
    end

    def valid_item_name?(name)
      !!(name =~ /\A[-_ 0-9a-zA-Z]+\Z/)
    end

    def register_state_item(item)
      name = item.name
      if @state_items[name]
        raise "Duplicate item name: #{name}! Failing!"
      end
      @state_items[name] = item
      if item.zone?
        @zones.push(item)
      end
      if @finished_init
        send_notification(type: "new item", zone: item.zone_name, location: item.location_name, actor: name)
      end
      item
    end

    # This method unregisters a StateItem from the engine. The method
    # assumes other items don't refer to the item being
    # unregistered. {#unregister_state_item} will try to perform basic
    # cleanup, but calling it *can* leave dangling references.
    #
    # @param [Demiurge::StateItem] item The item to unregister
    # @return [void]
    # @since 0.0.1
    def unregister_state_item(item)
      loc = item.location
      loc.ensure_does_not_contain(item.name)
      zone = item.zone
      zone.ensure_does_not_contain(item.name)
      @state_items.delete(item.name)
      @zones -= [item]
      nil
    end

    private
    # This sets the Engine's internal state from a structured array of
    # items. It is normally used via load_state_from_dump.
    def state_from_structured_array(arr)
      options = options.dup.freeze unless options.frozen?

      @finished_init = false
      @state_items = {}
      @zones = []

      arr.each do |type, name, state|
        register_state_item(StateItem.from_name_type(self, type.freeze, name.to_s.freeze, state))
      end

      unless @state_items["admin"]
        register_state_item(StateItem.from_name_type(self, "InertStateItem", "admin", {}))
      end

      @state_items["admin"].state["ticks"] ||= 0
      @state_items["admin"].state["notification_id"] ||= 0
      @state_items["admin"].state["intention_id"] ||= 0

      nil
    end
    public

    # This loads the Engine's state from structured
    # {Demiurge::StateItem} state that has been serialized. This
    # method handles reinitializing, signaling and whatnot. Use this
    # method to restore state from a JSON dump or a hypothetical
    # scenario that didn't work out.
    #
    # @param arr [Array] {Demiurge::StateItem} structured state in the form of Ruby objects
    # @return [void]
    # @since 0.0.1
    def load_state_from_dump(arr)
      send_notification(type: "load_state_start", actor: nil, location: nil, zone: "admin")
      state_from_structured_array(arr)
      finished_init
      send_notification(type: "load_state_end", actor: nil, location: nil, zone: "admin")
      flush_notifications
    end

    # Internal methods used by subscribe_to_notifications for notification matching.
    private
    def notification_spec(s)
      return s if s == :all
      if s.respond_to?(:each)
        return s.map { |s| notification_entity(s) }
      end
      return [notification_entity(s)]
    end

    def notification_entity(s)
      s = s.to_s if s.is_a?(Symbol)
      s = s.name if s.respond_to?(:name) # Demiurge Entities should be replaced by their names
      raise "Unrecognized notification entity: #{s.inspect}!" unless s.is_a?(String)
      s
    end
    public

    # This method 'subscribes' a block to various types of
    # notifications. The block will be called with the notifications
    # when they occur. A "specifier" for this method means either the
    # special symbol +:all+ or an Array of Symbols or Strings to show
    # what values a notification may have for the given field. For
    # fields that might indicate Demiurge items such as "zone" or
    # "actor" the value should be the Demiurge item *name*, not the
    # item itself.
    #
    # When a notification occurs that matches the subscription, the
    # given block will be called with a hash of data about that
    # notification.
    #
    # The tracker is supplied to allow later unsubscribes. Pass a
    # unique tracker object (usually a String or Symbol) when
    # subscribing, then pass in the same one when unsubscribing.
    #
    # At a minimum, subscriptions should include a zone to avoid
    # subscribing to all such notifications everywhere in the engine.
    # Engine-wide subscriptions become very inefficient very quickly.
    #
    # Notifications only have a few mandatory fields - type, actor,
    # zone and location. The location and/or actor can be nil in some
    # cases, and the zone can be "admin" for engine-wide events. If
    # you wish to subscribe based on other properties of the
    # notification then you'll need to pass a custom predicate to
    # check each notification. A "predicate" just means it's a proc
    # that returns true or false, depending whether a notification
    # matches.
    #
    # @example Subscribe to all notification types at a particular location
    # subscribe_to_notifications(zone: "my zone name", location: "my location") { |h| puts "Got #{h.inspect}!" }
    #
    # @example Subscribe to all "say" notifications in my same zone
    # subscribe_to_notifications(zone: "my zone", type: "say") { |h| puts "Somebody said something!" }
    #
    # @example Subscribe to all move_to notifications for a specific actor, with a tracker for future unsubscription
    # subscribe_to_notifications(zone: ["one", "two", "three"], type: "move_to", actor: "bozo the clown", tracker: "bozo move tracker") { |h| bozo_move(h) }
    #
    # @example Subscribe to notifications matching a custom predicate
    # subscribe_to_notifications(zone: "green field", type: "joyous dance", predicate: proc { |h| h["info"]["subtype"] == "butterfly wiggle" }) { |h| process(h) }
    #
    # @param type [:all, String, Array<Symbol>, Array<String>] A specifier for what Demiurge notification names to subscribe to
    # @param zone [:all, String, Array<Symbol>, Array<String>] A specifier for what Zone names match this subscription
    # @param location [:all, String, Array<Symbol>, Array<String>] A specifier for what location names match this subscription
    # @param predicate [Proc, nil] Call this proc on each notification to see if it matches this subscription
    # @param actor [:all, String, Array<Symbol>, Array<String>] A specifier for what Demiurge item name(s) must be the actor in a notification to match this subscription
    # @param tracker [Object, nil] To unsubscribe from this notification later, pass in the same tracker to {#unsubscribe_from_notifications}, or another object that is +==+ to this tracker. A tracker is most often a String or Symbol. If the tracker is nil, you can't ever unsubscribe.
    # @return [void]
    # @since 0.0.1
    def subscribe_to_notifications(type: :all, zone: :all, location: :all, predicate: nil, actor: :all, tracker: nil, &block)
      sub_structure = {
        type: notification_spec(type),
        zone: notification_spec(zone),
        location: notification_spec(location),
        actor: notification_spec(actor),
        predicate: predicate,
        tracker: tracker,
        block: block,
      }
      @subscriptions_by_tracker[tracker] ||= []
      @subscriptions_by_tracker[tracker].push(sub_structure)
      nil
    end

    # When you subscribe to a notification with
    # {#subscribe_to_notifications}, you may optionally pass a non-nil
    # tracker with the subscription.  If you pass that tracker to this
    # method, it will unsubscribe you from that notification. Multiple
    # subscriptions can use the same tracker and they will all be
    # unsubscribed at once. For that reason, you should use a unique
    # tracker if you do *not* want other code to be able to
    # unsubscribe you from notifications.
    #
    # @param tracker [Object] The tracker from which to unsubscribe
    # @return [void]
    # @since 0.0.1
    def unsubscribe_from_notifications(tracker)
      raise "Tracker must be non-nil!" if tracker.nil?
      @subscriptions_by_tracker.delete(tracker)
    end

    # Queue a notification to be sent later by the engine. The
    # notification must include at least type, zone, location and
    # actor and may include a hash of additional data, which should be
    # serializable to JSON (i.e. use only basic data types.)
    #
    # @param type [String] The notification type of this notification
    # @param zone [String, nil] The zone name for this notification. The special "admin" zone name is used for engine-wide events
    # @param location [String, nil] The location name for this notification, or nil if no location
    # @param actor [String, nil] The name of the acting item for this notification, or nil if no item is acting
    # @param data [Hash] Additional data about this notification; please use String keys for the Hash
    # @return [void]
    # @since 0.0.1
    def send_notification(data = {}, type:, zone:, location:, actor:)
      raise "Notification type must be a String, not #{type.class}!" unless type.is_a?(String)
      raise "Location must be a String, not #{location.class}!" unless location.is_a?(String) || location.nil?
      raise "Zone must be a String, not #{zone.class}!" unless zone.is_a?(String)
      raise "Acting item must be a String or nil, not #{actor.class}!" unless actor.is_a?(String) || actor.nil?

      @state_items["admin"].state["notification_id"] += 1

      cleaned_data = {}
      data.each do |key, val|
        # TODO: verify somehow that this is JSON-serializable?
        cleaned_data[key.to_s] = val
      end
      cleaned_data.merge!("type" => type, "zone" => zone, "location" => location, "actor" => actor, "id" => @state_items["admin"].state["notification_id"])

      @queued_notifications.push(cleaned_data)
    end

    # Send out any pending notifications that have been queued. This
    # will normally happen at least once per tick in any case, but may
    # happen more often.  If this occurs during the Engine's tick,
    # certain ordering issues may occur. Normally it's best to let the
    # Engine call this method during the tick, and to only call it
    # manually when no tick is occurring.
    #
    # @return [void]
    # @since 0.0.1
    def flush_notifications
      infinite_loop_detector = 0
      # Dispatch the queued notifications. Then, dispatch any
      # notifications that resulted from them.  Then, keep doing that
      # until the queue is empty.
      until @queued_notifications.empty?
        infinite_loop_detector += 1
        if infinite_loop_detector > 20
          raise TooManyNotificationLoopsError.new("Over 20 batches of notifications were dispatched in the same call! Error and die!", "last batch" => @queued_notifications.map { |n| n.class.to_s })
        end

        current_notifications = @queued_notifications
        @queued_notifications = []
        current_notifications.each do |cleaned_data|
          @subscriptions_by_tracker.each do |tracker, sub_structures|
            sub_structures.each do |sub_structure|
              next unless sub_structure[:type] == :all || sub_structure[:type].include?(cleaned_data["type"])
              next unless sub_structure[:zone] == :all || sub_structure[:zone].include?(cleaned_data["zone"])
              next unless sub_structure[:location] == :all || sub_structure[:location].include?(cleaned_data["location"])
              next unless sub_structure[:actor] == :all || sub_structure[:actor].include?(cleaned_data["actor"])
              next unless sub_structure[:predicate] == nil || sub_structure[:predicate] == :all || sub_structure[:predicate].call(cleaned_data)

              sub_structure[:block].call(cleaned_data)
            end
          end
        end
      end
    end
  end

  # A StateItem encapsulates a chunk of state. It provides behavior to
  # the bare data. Note that the {Demiurge::ActionItem} child class
  # makes StateItem easier to use by providing a simple block DSL
  # instead of requiring raw calls with the engine API.

  # Items a user would normally think about (zones, locations, agents,
  # etc) inherit from StateItem, often indirectly. The StateItem
  # itself might be highly abstract, and might not correspond to a
  # user's idea of a specific thing in a specific place. For example,
  # a global weather pattern across many zones is not a single
  # "normal" item. But it could be a single StateItem as the weather
  # changes and potentially reacts over time.

  # StateItems are transient and can be created, recreated or
  # destroyed without warning. They need to be hooked up to the
  # various Ruby code for their actions. The code for actions isn't
  # serialized. Instead, each action is referred to by a name scoped
  # to the item's registered name.  All item-name/action-name
  # combinations are registed in the {Demiurge::Engine} when the
  # {Demiurge::DSL} reads the Ruby World Files. This means an action
  # can be referred to by its name when serialized, but the actual
  # code changes any time the world files are reloaded.

  # For items with more convenient behavior to them see ActionItem,
  # and/or specific classes like Agent, Zone, Location and so on.

  # StateItems can be serialized at any time to "structured array"
  # format. That format consists of a set of Plain Old Ruby Objects
  # (POROs) which are guaranteed to be serializable as JSON, and thus
  # consist of only basic data structures like Strings, Arrays,
  # Booleans and Hashes. A single StateItem will serialize itself to a
  # short Array of this form: ["ObjectType", "item name",
  # state_hash]. The ObjectType is the type registered with the
  # engine, such as "ActionItem". The "item name" is the object-unique
  # item name. And the state_hash is a JSON-serializable Ruby Hash
  # with the object's current state. A dump of multiple StateItems
  # will be an Array of these Arrays.

  class StateItem
    # @return [String] The unique, registered or registerable name of this {Demiurge::StateItem}
    # @since 0.0.1
    attr_reader :name

    # @return [String] The default StateItem type of this item. Can be overridden by child classes.
    # @since 0.0.1
    def state_type
      self.class.name.split("::")[-1]
    end

    # The constructor. This does not register the StateItem with the
    # Engine. For that, see {Demiurge::Engine#register_state_item}.
    #
    # @see Demiurge::Engine#register_state_item
    # @return [void]
    # @since 0.0.1
    def initialize(name, engine, state)
      @name = name
      @engine = engine
      @state = state
    end

    # This method determines whether the item will be treated as a
    # top-level zone.  Inheriting from Demiurge::Zone will cause that
    # to occur. So will redefining the zone? method to return true.
    # Whether zone? returns true should not depend on state, which may
    # not be set when this method is called.
    #
    # @return [Boolean] Whether this item is considered a Zone.
    # @since 0.0.1
    def zone?
      self.is_a?(::Demiurge::Zone)
    end

    # This method determines whether the item will be treated as an
    # agent.  Inheriting from Demiurge::Agent will cause that to
    # occur. So will redefining the agent? method to return true.
    # Whether agent? returns true should not depend on state, which
    # may not be set when this method is called.
    #
    # @return [Boolean] Whether this item is considered an Agent.
    # @since 0.0.1
    def agent?
      self.is_a?(::Demiurge::Agent)
    end

    # Return this StateItem's current state in a JSON-serializable
    # form.
    #
    # @return [Object] The JSON-serializable state, usually a Hash
    # @since 0.0.1
    def state
      @state
    end

    # The StateItem's serialized state in structured array format.
    #
    # @see Demiurge::StateItem
    # @return [Array] The serialized state
    # @since 0.0.1
    def get_structure(options = {})
      [state_type, @name, @state]
    end

    # Create a single StateItem from structured array format
    #
    # @see Demiurge::StateItem
    # @return [Demiurge::StateItem] The deserialized StateItem
    # @since 0.0.1
    def self.from_name_type(engine, type, name, state, options = {})
      engine.get_type(type).new(name, engine, state)
    end

    def intentions_for_next_step(*args)
      raise "StateItem must be subclassed to be used!"
    end

  end

  # An Intention is an unresolved event. Some part of the simulated
  # world "wishes" to take an action. This need not be a sentient
  # being - any change to the world should occur with an Intention
  # then being resolved into changes in state and events -- or
  # not. It's also possible for an intention to resolve to nothing at
  # all. For instance, an intention to move in an impossible direction
  # could simply resolve with no movement, no state change and no event.

  # Intentions go through verification, resolution and eventually
  # notification.

  # Intentions are not, in general, serializable. They normally
  # persist for only a single tick. To persist an intention for most StateItems,
  # consider persisting action names instead.

  class Intention
    # Subclasses of intention can require all sorts of things to
    # specify what the intention is.
    def initialize(engine)
      @cancelled = false
      @engine = engine
    end

    def cancel(reason, info = {})
      @cancelled = true
      @cancelled_by = caller(1, 1)
      @cancelled_reason = reason
      @cancelled_info = info
      cancel_notification
    end

    # This can be overridden for more specific notifications
    def cancel_notification
      # "Silent" notifications are things like an agent's action queue
      # being empty so it cancels its intention.  These are normal
      # operation and nobody is likely to need notification every
      # tick that they didn't ask to do anything so they didn't.
      return if @cancelled_info && @cancelled_info["silent"]
      @engine.send_notification({
                                  :reason => @cancelled_reason,
                                  :by => @cancelled_by,
                                  :id => @intention_id,
                                  :intention_type => self.class.to_s,
                                  :info => @cancelled_info
                                },
                                type: "intention_cancelled", zone: "admin", location: nil, actor: nil)
    end

    def cancelled?
      @cancelled
    end

    def allowed?(engine, options = {})
      raise "Unimplemented 'allowed?' for intention: #{self.inspect}!"
    end

    def apply(engine, options = {})
      raise "Unimplemented 'apply' for intention: #{self.inspect}!"
    end

    # When an intention is "offered", that means appropriate other
    # entities have a chance to modify or cancel the intention. For
    # instance, a movement action in a room should be offered to that
    # room, which may trigger a special action (e.g. trap) or change
    # the destination of the action (e.g. exits, slippery ice,
    # spinning spaces.)
    def offer(engine, intention_id, options = {})
      raise "Unimplemented 'offer' for intention: #{self.inspect}!"
    end

    def try_apply(engine, intention_id, options = {})
      @intention_id = intention_id
      unless allowed?(engine, options)
        # Certain intentions can send an "intention failed" notification.
        # Such a notification would be sent from here.
        return
      end
      offer(engine, intention_id, options)
      return if cancelled? # Notification should already have been sent out
      apply(engine, options)
    end
  end
end
