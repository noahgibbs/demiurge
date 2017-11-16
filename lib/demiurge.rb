require "demiurge/version"
require "demiurge/util"

# Predeclare classes that other required files will use.
module Demiurge
  class StateItem; end
  class Intention < StateItem; end
end

require "demiurge/action_item"
require "demiurge/inert_state_item"
require "demiurge/zone"
require "demiurge/location"
require "demiurge/agent"

require "multi_json"

module Demiurge
  class Engine
    include ::Demiurge::Util # For copyfreeze and deepcopy

    attr_reader :ticks

    # When initializing, "types" is a hash mapping type name to the
    # class that implements that name. Usually the name is the same as
    # the class name with the module optionally stripped off.
    # State is an array of state items, each an array with the type
    # name first, followed by the item name (unique) and the current
    # state of that item as a hash.
    def initialize(types: {}, state: [])
      if types
        types.each do |tname, tval|
          register_type(tname, tval)
        end
      end
      state_from_structured_array(state || [])
      @subscriptions_by_tracker = {}
      @ticks = 0
      @notification_id = 0
      @intention_id = 0
      @queued_notifications = []
      @queued_intentions = []
      nil
    end

    # Used after things are basically in place to assign double-sided
    # state like what items and containers are where.  It should be
    # called if a new world is being created from DSL files, but
    # should be skipped if you're restoring state from a dump.
    def finished_init
      raise("Duplicate finished_init call to engine!") if @finished_init
      @state_items.values.each { |obj| obj.finished_init() if obj.respond_to?(:finished_init) }
      @finished_init = true
    end

    def structured_state(options = { "copy" => false })
      dump = @state_items.values.map { |item| item.get_structure(options) }
      if options["copy"]
        dump = deepcopy(dump)  # Make sure it doesn't share state...
      end
      dump
    end

    def item_by_name(name)
      @state_items[name]
    end

    def zones
      @zones
    end

    def all_item_names
      @state_items.keys
    end

    def queue_intention(intention)
      @intention_id += 1
      @queued_intentions.push [@intention_id, intention]
    end

    def queue_item_intentions(options = {})
      next_step_intentions.each { |i| queue_intention(i) }
    end

    def next_step_intentions(options = {})
      @zones.flat_map { |item| item.intentions_for_next_step(options) || [] }
    end

    def flush_intentions(options = { })
      state_backup = structured_state("copy" => true)

      infinite_loop_detector = 0
      until @queued_intentions.empty?
        infinite_loop_detector += 1
        if infinite_loop_detector > 20
          raise "Over 20 batches of intentions were dispatched in the same call! Error and die!"
        end

        intentions = @queued_intentions
        @queued_intentions = []
        begin
          intentions.each do |id, a|
            a.try_apply(self, id, options)
          end
        rescue
          STDERR.puts "Exception when updating! Throwing away speculative state!"
          load_state_from_dump(state_backup)
          raise
        end
      end

      send_notification({}, notification_type: "tick finished", location: "", zone: "", item_acting: nil)
      @ticks += 1
    end

    def advance_one_tick(options = {})
      queue_item_intentions(options)
      flush_intentions
      flush_notifications
    end

    def get_type(t)
      raise("Not a valid type: #{t.inspect}!") unless @klasses && @klasses[t]
      @klasses[t]
    end

    def register_type(name, klass)
      @klasses ||= {}
      if @klasses[name] && @klasses[name] != klass
        raise "Re-registering name with different type! Name: #{name.inspect} Class: #{klass.inspect} OldClass: #{@klasses[name].inspect}!"
      end
      @klasses[name] ||= klass
    end

    # StateItems are transient, but need to be hooked up to the
    # various (code) actions for doing various things.  Those actions
    # aren't serialized (ew), but instead are referred to by name, and
    # the engine loads up all the item-name/action-name combinations
    # when it reads the Ruby source files. This means an action can be
    # referred to by its name when serialized, but the actual code
    # changes any time the world files do - at least, if you reboot
    # now and then.

    # I've tried moving the actions back into StateItems, which makes
    # more sense with non-transient StateItems. It can be hard to do a
    # state restore from World Files in this way, though.

    def register_actions_by_item_and_action_name(item_actions)
      @item_actions ||= {}
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
        send_notification(notification_type: "new item", zone: item.zone_name, location: item.location_name, item_acting: name)
      end
      item
    end

    # This sets the Engine's internal state from a structured array of
    # items.  This is a good way, for instance, to restore state from
    # a JSON dump or a hypothetical that didn't work out.
    def state_from_structured_array(arr, options = {})
      options = options.dup.freeze unless options.frozen?

      @finished_init = false
      @state_items = {}
      @state = {}
      @zones = []

      arr.each do |type, name, state|
        register_state_item(StateItem.from_name_type(self, type.freeze, name.to_s.freeze, state, options))
      end
      nil
    end

    def load_state_from_dump(arr, options = {})
      state_from_structured_array(arr, options)
      finished_init
    end

    # Internal method used by subscribe_to_notifications for notification matching.
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
    # when they occur.
    def subscribe_to_notifications(notification_type: :all, zone: :all, location: :all, predicate: nil, item_acting: :all, tracker: nil, &block)
      sub_structure = {
        type: notification_spec(notification_type),
        zone: notification_spec(zone),
        location: notification_spec(location),
        item_acting: notification_spec(item_acting),
        predicate: predicate,
        tracker: tracker,
        block: block,
      }
      @subscriptions_by_tracker[tracker] ||= []
      @subscriptions_by_tracker[tracker].push sub_structure
    end

    def unsubscribe_from_notifications(tracker)
      @subscriptions_by_tracker[tracker].each do |subscription|
        # Remove from other structures tracking subscriptions
      end
      @subscriptions_by_tracker.delete(tracker)
    end

    def send_notification(data = {}, notification_type:, zone:, location:, item_acting:)
      raise "Notification type must be a String, not #{notification_type.class}!" unless notification_type.is_a?(String)
      raise "Location must be a String, not #{location.class}!" unless location.is_a?(String) || location.nil?
      raise "Zone must be a String, not #{zone.class}!" unless zone.is_a?(String)
      raise "Acting item must be a String or nil, not #{item_acting.class}!" unless item_acting.is_a?(String) || item_acting.nil?

      @notification_id += 1

      cleaned_data = {}
      data.each do |key, val|
        # TODO: verify somehow that this is JSON-serializable?
        cleaned_data[key.to_s] = val
      end
      cleaned_data.merge!("type" => notification_type, "zone" => zone, "location" => location, "actor" => item_acting, "item acting" => item_acting, "id" => @notification_id)

      @queued_notifications.push(cleaned_data)
    end

    def flush_notifications
      infinite_loop_detector = 0
      # Dispatch the queued notifications. Then, dispatch any
      # notifications that resulted from them.  Then, keep doing that
      # until the queue is empty.
      until @queued_notifications.empty?
        infinite_loop_detector += 1
        if infinite_loop_detector > 20
          raise "Over 20 batches of notifications were dispatched in the same call! Error and die!"
        end

        current_notifications = @queued_notifications
        @queued_notifications = []
        current_notifications.each do |cleaned_data|
          @subscriptions_by_tracker.each do |tracker, sub_structures|
            sub_structures.each do |sub_structure|
              next unless sub_structure[:type] == :all || sub_structure[:type].include?(cleaned_data["type"])
              next unless sub_structure[:zone] == :all || sub_structure[:zone].include?(cleaned_data["zone"])
              next unless sub_structure[:location] == :all || sub_structure[:location].include?(cleaned_data["location"])
              next unless sub_structure[:item_acting] == :all || sub_structure[:item_acting].include?(cleaned_data["item acting"])
              next unless sub_structure[:predicate] == nil || sub_structure[:predicate] == :all || sub_structure[:predicate].call(cleaned_data)

              sub_structure[:block].call(cleaned_data)
            end
          end
        end
      end
    end
  end

  # A StateItem encapsulates a chunk of state. It provides behavior to
  # the bare data. Note that ActionItem, defined elsewhere, makes this
  # easier to use by providing a simple block DSL instead of requiring
  # raw calls with the engine API.

  # Objects you'd normally think about (zones, locations, agents, etc)
  # inherit from StateItem, often indirectly. The StateItem by itself
  # is allowed to be highly abstract, and may have no convenient way
  # to treat it like a "thing" in a "place." For instance, a global
  # weather pattern across many zones lacks most 'normal' behaviors,
  # but it makes a perfectly good StateItem as it changes and
  # potentially reacts over time.

  # For items with more convenient behavior to them see ActionItem,
  # and/or specific classes like Agent, Zone, Location and so on.

  class StateItem
    attr_reader :name

    def state_type
      self.class.name.split("::")[-1]
    end

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
    def zone?
      self.is_a?(::Demiurge::Zone)
    end

    # This method determines whether the item will be treated as an
    # agent.  Inheriting from Demiurge::Agent will cause that to
    # occur. So will redefining the agent? method to return true.
    # Whether agent? returns true should not depend on state, which
    # may not be set when this method is called.
    def agent?
      self.is_a?(::Demiurge::Agent)
    end

    def state
      @state
    end

    def get_structure(options = {})
      [state_type, @name, @state]
    end

    # Create a single StateItem from structured (generally frozen) state
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

  # TODO: with non-transient StateItems, I think we can skip passing "engine" into all of these...
  # Basically, anything can take a StateItem to its constructor and get everything it needs.
  class Intention
    # Subclasses of intention can require all sorts of things to
    # specify what the intention is.  But the base class doesn't have
    # any required arguments to its constructor.
    def initialize()
      @cancelled = false
    end

    def cancel(reason)
      @cancelled = true
      @cancelled_by = caller(1, 1)
      @cancelled_reason = reason
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
      unless allowed?(engine, options)
        # Certain intentions can send an "intention failed" notification.
        # Such a notification would be sent from here.
        return
      end
      offer(engine, intention_id, options)
      if cancelled?
        # Similarly, intentions can send an "intention cancelled" notification.
        # The relevant variables are @cancelled_by and @cancelled_reason
        return
      end
      apply(engine, options)
    end
  end
end
