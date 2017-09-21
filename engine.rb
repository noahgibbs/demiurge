require "multi_json"

# TODO: how to refactor the engine? There's immutable state, there are
# rules in StateItems and Engines. But how to put it together? Perhaps
# StateItems and Engines become rules that transform state
# (e.g. functions that return new state.) But then, how to handle
# cases where a StateItem messes with various state that doesn't
# "belong" to it? Create a briefly-mutable new copy of the state and
# then freeze it? Hard to figure out how to do all this both cleanly
# and without large, sprawling copies of huge JSON state trees, but
# without a given StateItem having to declare exactly which state it
# can touch and who else can't touch it.

# STATUS UPDATE: okay, I now have an inefficient but very safe idea
# for how to do this and have mostly implemented it. Basically, make a
# new copied state tree, update it with the intentions, then
# copyfreeze it to make the state tree for the following
# timestep. That's fine, but I'm still doing a poor job of explicitly
# managing the JSON-type state tree separate from the "dedicated
# objects with references into the JSON data" parts. Right now, @state
# is the latter and the former is basically implicit rather than
# explicit. But if you change the frozen tree data, you need to change
# out the objects too, with the current approach. Argh!

module Ygg
  class StoryEngine
    INIT_PARAMS = [ "state" ]

    def initialize(params)
      illegal_params = params.keys - INIT_PARAMS.flatten
      raise("Illegal params passed to StoryEngine.new: #{illegal_params.inspect}!") unless illegal_params.empty?

      @state = Ygg::StateTree.state_from_structured_array(params["state"] || [])
      nil
    end

    def structured_state(options = {})
      options = options.dup.freeze unless options.frozen?

      StateTree.structured_array_from_state(@state, options)
    end

    def next_step_intentions(options = {})
      options = options.dup.freeze unless options.frozen?
      @state.values.flat_map { |item| item.intentions_for_next_step(options) }
    end

    def item_by_name(name)
      @state[name]
    end

    def apply_intentions(intentions, options = {})
      options = options.dup.freeze
      speculative_state = StateTree.deepcopy(@state)
      valid_state = @state
      @state = speculative_state

      begin
        intentions.each do |a|
          a.try_apply(self, options)
        end
      rescue
        STDERR.puts "Exception when updating! Throwing away speculative state!"
        @state = valid_state
      end

      # Make sure to copyfreeze. Nobody gets to keep references to the state-tree's internals.
      @state = StateTree.copyfreeze(speculative_state)
    end

  end

  class StateTree
    def self.state_from_array(arr, options = {})
      options = options.dup.freeze unless options.frozen?
      state_hash = {}
      arr.each do |item|
        state_hash[item.name] = item
      end
      state_hash.freeze
    end

    def self.state_from_structured_array(arr, options = {})
      options = options.dup.freeze unless options.frozen?

      items = arr.map { |type, state| StateItem.from_structure(type.freeze, copyfreeze(state), options) }

      state_from_array items, options
    end

    def self.structured_array_from_state(state_hash, options = {})
      options = options.dup.freeze unless options.frozen?

      state_hash.values.map { |item| item.get_structure(options) }
    end

    # This operation duplicates standard data that can be reconstituted from
    # JSON, to make a frozen copy.
    def self.copyfreeze(items)
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
    def self.deepcopy(items)
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
    def initialize(state)
      @state = state
    end

    def get_structure(options = {})
      [self.class.name, @state]
    end

    # Create a single item from structured (generally frozen) state
    def self.from_structure(type, state, option = {})
      get_type(type).new(state)
    end

    def self.get_type(t)
      raise("Not a valid type: #{t.inspect}!") unless @@klasses[t]
      @@klasses[t]
    end

    def self.register_type(name, klass)
      @@klasses ||= {}
      if @@klasses[name] && @@klasses[name] != klass
        raise "Re-registering name with different type! Name: #{name.inspect} Class: #{klass.inspect} OldClass: #{@@klasses[name].inspect}!"
      end
      @@klasses[name] ||= klass
    end

    def name
      @state["name"]  # By default, at least
    end

    def intentions_for_next_step(*args)
      raise "StateItem must be subclassed to be used directly!"
    end

  end

  class Intention < StateItem
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
