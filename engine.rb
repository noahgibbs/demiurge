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

module Ygg
  class StoryEngine
    INIT_PARAMS = [ [:state_array, :json_file] ]

    def initialize(params)
      illegal_params = params.keys - INIT_PARAMS.flatten
      raise("Illegal params passed to StoryEngine.new: #{illegal_params.inspect}!") unless illegal_params.empty?

      INIT_PARAMS.select { |p| p.respond_to?(:each) }.each do |param_group|
        group_keys = params.keys.select { |pk| param_group.include?(pk) }

	raise("Can pass at most one of #{param_group.map(&:to_s).join(", ")}, you passed #{group_keys.map(&:to_s).join(" and ")}!") if group_keys.size > 1
      end

      if params[:json_file]
        json_state = MultiJson.load(File.read(params[:json_file]))
	raise("JSON file must contain a top-level array!") unless json_state.is_a?(Array)
	@state = state_from_serialized_array(json_state)
      else
        @state = state_from_array(params[:state_array] || [])
      end
    end

    def state_from_array(arr, options = {})
      options = options.dup.freeze
      state_hash = {}
      arr.each do |item|
        state_hash[item.name] = item
      end
      state_hash
    end

    def state_from_serialized_array(arr, options = {})
      options = options.dup.freeze

      items = arr.map { |type, state| StateItem.deserialize(type, state, options) }

      state_from_array items
    end

    def next_step_intentions(options = {})
      options = options.dup.freeze
      @state.values.flat_map { |item| item.intentions_for_next_step(options) }
    end

    def item_by_name(name)
      @state[name]
    end

    def apply_intentions(intentions, options = {})
      options = options.dup.freeze

      intentions.each do |a|
        a.try_apply(self, options)
      end
    end

  end

  class StateItem
    def initialize(state)
      @state = state
    end

    def serialize(options = {})
      MultiJSON.dump( [self.class.name, @state] )
    end

    # Deserialize a single item from state, not JSON
    def self.deserialize(type, state, option = {})
      get_type(type).new(state)
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
      when String
        items.dup.freeze
      else
        STDERR.puts "Unrecognized item type #{items.class.inspect} in copyfreeze!"
        items.dup.freeze
      end
    end

    def self.get_type(t)
      raise("Not a valid type: #{t.inspect}!") unless @@klasses[t]
      @@klasses[t]
    end

    def self.register_type(name, klass)
      @@klasses ||= {}
      @@klasses[name] ||= klass
    end

    def name
      @state[:name]  # By default, at least
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
