require "demiurge/version"

# Predeclare classes that other required files will use.
module Demiurge
  class StateItem; end
  class Intention < StateItem; end
end

require "demiurge/action_item"
require "demiurge/zone"
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

    def state_from_structured_array(arr, options = {})
      options = options.dup.freeze unless options.frozen?

      @state_items = {}
      @state = {}

      arr.each do |type, name, state|
        @state[name] = state
        @state_items[name] = StateItem.from_name_type(self, type.freeze, name.freeze, options)
      end
      @zones = @state_items.values.select { |item| item.zone? }
    end

    # This operation duplicates standard data that can be reconstituted from
    # JSON, to make a frozen copy.
    def copyfreeze(items)
      case items
      when Hash
        result = {}
        items.each do |k, v|
          result[k] = copyfreeze(v)
        end
        result.freeze
      when Array
        items.map { |i| copyfreeze(i) }
      when Numeric
        items
      when NilClass
        items
      when TrueClass
        items
      when FalseClass
        items
      when String
        if items.frozen?
          items
        else
          items.dup.freeze
	end
      else
        STDERR.puts "Unrecognized item type #{items.class.inspect} in copyfreeze!"
        items.dup.freeze
      end
    end

    # This operation duplicates standard data that can be reconstituted from
    # JSON, to make a non-frozen copy.
    def deepcopy(items)
      case items
      when Hash
        result = {}
        items.each do |k, v|
          result[k] = deepcopy(v)
        end
        result
      when Array
        items.map { |i| deepcopy(i) }
      when Numeric
        items
      when NilClass
        items
      when TrueClass
        items
      when FalseClass
        items
      when String
        items.dup
      else
        STDERR.puts "Unrecognized item type #{items.class.inspect} in copyfreeze!"
        items.dup
      end
    end

  end

  # A StateItem encapsulates a chunk of frozen, immutable state. It
  # provides behavior to the bare data. Note that ActionItem, defined
  # elsewhere, makes this easier to use by providing a simple block
  # DSL instead of requiring raw calls with the engine API.
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

    # Create a single item from structured (generally frozen) state
    def self.from_name_type(engine, type, name, options = {})
      engine.get_type(type).new(name, engine)
    end

    def intentions_for_next_step(*args)
      raise "StateItem must be subclassed to be used directly!"
    end

  end

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
