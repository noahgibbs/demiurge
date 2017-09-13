require "multi_json"

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

      items = arr.map do |a|
        type, state = *a
        StateItem.deserialize(type, state, options)
      end

      state_from_array items
    end

    def next_step_actions(options = {})
      options = options.dup.freeze
      @state.values.flat_map { |item| item.actions_for_next_step(options) }
    end

    def item_by_name(name)
      @state[name]
    end

    def apply_actions(actions, options = {})
      options = options.dup.freeze

      actions.each do |a|
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

    def actions_for_next_step(*args)
      raise "StateItem must be subclassed to be used directly!"
    end

  end

  class Action < StateItem
    def allowed?(engine, options = {})
      raise "Unimplemented action!"
    end

    def apply(engine, options = {})
      raise "Unimplemented action!"
    end

    def try_apply(engine, options = {})
      apply(engine, options) if allowed?(engine, options)
    end
  end

end
