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
    #include ::Demiurge::Util # For copyfreeze and deepcopy

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

    def structured_state(options = {})
      @state_items.values.map { |item| item.get_structure(options) }
    end

    def next_step_intentions(options = {})
      @zones.flat_map { |item| item.intentions_for_next_step(options) || [] }
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

    def apply_intentions(intentions, options = { })
      state_backup = structured_state()

      begin
        intentions.each do |a|
          a.try_apply(self, options)
        end
      rescue
        STDERR.puts "Exception when updating! Throwing away speculative state!"
        state_from_structured_array(state_backup)
        raise
      end

      send_notification({}, notification_type: "tick finished", location: "", zone: "", item_acting: nil)
      @ticks += 1
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
    end

    # This sets the Engine's internal state from a structured array of
    # items.  This is a good way, for instance, to restore state from
    # a JSON dump or a hypothetical that didn't work out.
    def state_from_structured_array(arr, options = {})
      options = options.dup.freeze unless options.frozen?

      @state_items = {}
      @state = {}
      @zones = []

      arr.each do |type, name, state|
        register_state_item(StateItem.from_name_type(self, type.freeze, name.to_s.freeze, state, options))
      end
      nil
    end

    # Internal method used by subscribe_to_notifications for notification matching.
    private
    def notification_spec(s)
      return s if s == :all
      if s.respond_to?(:each)
        return s.map { |item| notification_spec(item) }
      end
      return s.name if s.respond_to?(:name)  # Demiurge Entities should be replaced by their names
      s
    end
    public

    # This method 'subscribes' a block to various types of
    # notifications. The block will be called with the notifications
    # when they occur.
    def subscribe_to_notifications(notification_types: :all, zones: :all, locations: :all, predicate: nil, items: :all, tracker: nil, &block)
      sub_structure = {
        types: notification_spec(notification_types),
        zones: notification_spec(zones),
        locations: notification_spec(locations),
        items: notification_spec(items),
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
      raise "Location must be a String, not #{location.class}!" unless location.is_a?(String)
      raise "Zone must be a String, not #{zone.class}!" unless zone.is_a?(String)
      raise "Acting item must be a String or nil, not #{item_acting.class}!" unless item_acting.is_a?(String) || item_acting.nil?

      cleaned_data = {}
      data.each do |key, val|
        # TODO: verify somehow that this is JSON-serializable?
        cleaned_data[key.to_s] = val
      end
      cleaned_data.merge!("type" => notification_type, "zone" => zone, "location" => location, "item acting" => item_acting)

      @subscriptions_by_tracker.each do |tracker, sub_structures|
        sub_structures.each do |sub_structure|
          next unless sub_structure[:types] == :all || sub_structure[:types].include?(notification_type)
          next unless sub_structure[:zones] == :all || sub_structure[:zones].include?(zone)
          next unless sub_structure[:locations] == :all || sub_structure[:locations].include?(zone)
          next unless sub_structure[:items] == :all || sub_structure[:items].include?(item_acting)
          next unless sub_structure[:predicate] == nil || sub_structure[:predicate].call(notification_type: notification_type, zone: zone, location: location, item_acting: item_acting)

          sub_structure[:block].call(cleaned_data)
        end
      end
    end

  end

  # A StateItem encapsulates a chunk of frozen, immutable state. It
  # provides behavior to the bare data. Note that ActionItem, defined
  # elsewhere, makes this easier to use by providing a simple block
  # DSL instead of requiring raw calls with the engine API.
  #
  # Objects you'd normally think about (zones, locations, agents, etc)
  # inherit from StateItem, often indirectly. The StateItem by itself
  # is allowed to be highly abstract, and may have no convenient way
  # to treat it like a "thing" in a "place." For instance, a global
  # weather pattern across many zones lacks most 'normal' behaviors,
  # but it makes a perfectly good StateItem as it changes and
  # potentially reacts over time.
  #
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
  # could simply become no movement, no state change and no event.
  #
  # Intentions go through verification, resolution and eventually
  # notification.

  # TODO: with non-transient StateItems, I think we can skip passing "engine" into all of these...
  # Basically, anything can take a StateItem to its constructor and get everything it needs.
  class Intention
    def allowed?(engine, options = {})
      raise "Unimplemented intention!"
    end

    def apply(engine, options = {})
      raise "Unimplemented intention!"
    end

    def try_apply(engine, options = {})
      apply(engine, options) if allowed?(engine, options)
    end

    # An Intention can keep an Agent (or potentially other entity)
    # busy for some amount of time when it occurs. How long? That's a
    # collaboration between this method and the entity. This method
    # should return a number. By default, Agents will perform one unit
    # of intentions per round, but that's advisory - nothing stops
    # Bob-the-Octopus from performing more actions per round if that's
    # what Bob's Agent object thinks is appropriate. For that matter,
    # "Mercury's Avatar on Earth" could just allow queueing of
    # unlimited actions of any kind on every tick, though it's not
    # clear that'd make for a fun game entity.
    def busy_turns
      1
    end
  end
end
