require "demiurge/version"
require "demiurge/util"

# Predeclare classes that other required files will use.
module Demiurge
  class StateItem; end
  class Intention < StateItem; end
end

require "demiurge/action_item"
require "demiurge/zone"
require "demiurge/location"
require "demiurge/agent"

require "multi_json"

# Okay, so with state set per-object, and StateItem objects having no
# local copy, it becomes an interface question: how to write
# less-horrible code in a DSL setting to paper over the fact that the
# item doesn't control its own state, and has to be fully disposable.

# This makes it easy to run in "debug mode" where state and StateItems
# are both rotated constantly (destroyed and recreated) while allowing
# easier production runs where things can be mutated rather than
# frozen and replaced.

module Demiurge
  class Engine
    include ::Demiurge::Util # For copyfreeze and deepcopy

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
      nil
    end

    def structured_state(options = {})
      options = options.dup.freeze unless options.frozen?

      @state_items.values.map { |item| item.get_structure(options) }
    end

    def next_step_intentions(options = {})
      options = options.dup.freeze unless options.frozen?
      #@state_items.values.flat_map { |item| item.intentions_for_next_step(options) || [] }
      @zones.flat_map { |item| item.intentions_for_next_step(options) || [] }
    end

    def item_by_name(name)
      @state_items[name]
    end

    def state_for_item(name)
      @state[name]
    end

    def state_for_property(name, property)
      @state[name][property]
    end

    def set_state_for_property(name, property, value)
      @state[name][property] = value
    end

    def zones
      @zones
    end

    def apply_intentions(intentions, options = {})
      options = options.dup.freeze
      speculative_state = deepcopy(@state)
      valid_state = @state
      @state = speculative_state

      begin
        intentions.each do |a|
          a.try_apply(self, options)
        end
      rescue
        STDERR.puts "Exception when updating! Throwing away speculative state!"
        @state = valid_state
        raise
      end

      # Make sure to copyfreeze. Nobody gets to keep references to the state-tree's internals.
      @state = copyfreeze(speculative_state)
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
    #
    # A reasonable question: why not attach the actions to the state
    # items any time they're created? The short answer is that
    # StateItems may be transient, and we don't want to have to
    # remember all the code we loaded to let them reload
    # themselves. Instead we remember all loaded code in the engine.
    def register_actions_by_item_and_action_name(item_actions)
      @item_actions ||= {}
      item_actions.each do |item_name, act_hash|
        if @item_actions[item_name]
          dup_keys = @item_actions[item_name].keys | act_hash.keys
          raise "Duplicate item actions for #{item_name.inspect}! List: #{dup_keys.inspect}" unless dup_keys.empty?
          @item_actions[item_name].merge!(act_hash)
        else
          @item_actions[item_name] = act_hash
        end
      end
    end

    def action_for_item(item_name, action_name)
      unless @item_actions && @item_actions[item_name]
        raise "Can't get action #{item_name.inspect} / #{action_name.inspect} from #{@item_actions.inspect}!"
      end
      @item_actions[item_name][action_name]
    end

    def valid_item_name?(name)
      !!(name =~ /\A[-_ 0-9a-zA-Z]+\Z/)
    end

    # This sets the Engine's internal state from a structured array of
    # items.  This is a good way, for instance, to restore state from
    # a JSON dump or a hypothetical that didn't work out.
    def state_from_structured_array(arr, options = {})
      options = options.dup.freeze unless options.frozen?

      @state_items = {}
      @state = {}

      arr.each do |type, name, state|
        name = name.to_s
        if @state_items[name]
          raise "Duplicate item name: #{name}! Failing!"
        end
        @state[name] = state
        @state_items[name] = StateItem.from_name_type(self, type.freeze, name.freeze, options)
      end
      @zones = @state_items.values.select { |item| item.zone? }
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

    def initialize(name, engine)
      @name = name
      @engine = engine
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
      @engine.state_for_item(@name)
    end

    def get_structure(options = {})
      [state_type, @name, @engine.state_for_item(@name)]
    end

    # Create a single StateItem from structured (generally frozen) state
    def self.from_name_type(engine, type, name, options = {})
      engine.get_type(type).new(name, engine)
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
  end
end
