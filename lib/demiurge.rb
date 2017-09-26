require "demiurge/version"

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
  class StoryEngine
    INIT_PARAMS = [ "state", "types" ]

    def initialize(types: {}, state: {})
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
      @state_items.values.flat_map { |item| item.intentions_for_next_step(options) || [] }
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

    def state_from_structured_array(arr, options = {})
      options = options.dup.freeze unless options.frozen?

      @state_items = {}
      @state = {}

      arr.each do |type, name, state|
        @state_items[name] = StateItem.from_name_type(self, type.freeze, name.freeze, options)
        @state[name] = state
      end
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

  # A StateItem encapsulates a chunk of frozen, immutable state. It provides behavior to the bare data.
  class StateItem
    def state_type
      self.class.name.split("::")[-1]
    end

    def initialize(name, engine)
      @name = name
      @engine = engine
    end

    def get_structure(options = {})
      [state_type, @name, @engine.state_for_item(@name)]
    end

    # Create a single item from structured (generally frozen) state
    def self.from_name_type(engine, type, name, options = {})
      engine.get_type(type).new(name, engine)
    end

    def name
      @name
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
