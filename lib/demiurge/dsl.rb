require_relative "../demiurge"

module Demiurge
  class TopLevelBuilder
    def initialize
      @areas = []
      @locations = []
    end

    def area(name, &block)
      builder = AreaBuilder.new(name)
      builder.instance_eval(&block)
      @areas << builder.built_area
      @locations += builder.built_locations
      nil
    end

    def built_engine
      types = {
        "DslLocation" => DslLocation,
        "DslArea" => DslArea,
      }
      state = @areas + @locations
      engine = StoryEngine.new(types: types, state: state)
      engine
    end
  end

  class AreaBuilder
    def initialize(name)
      @name = name
      @locations = []
      @actions = {}
    end

    def location(name, &block)
      builder = LocationBuilder.new(name)
      builder.instance_eval(&block)
      location = builder.built_location
      @locations << location
      DslLocation.register_actions_by_item_and_action_name(location[1] => builder.actions)
      nil
    end

    def built_area
      [ "DslArea", @name, "location_names" => @locations.map { |l| l[1] } ]
    end

    def built_locations
      @locations
    end
  end

  class LocationBuilder
    attr_reader :actions

    def initialize(name)
      @name = name
      @everies = []
      @description = nil
      @actions = {}
    end

    def description(d)
      @description = d
    end

    def every_X_ticks(action_name, t, &block)
      @everies << { "action" => action_name, "every" => t, "counter" => 0 }
      @actions[action_name] = block
    end

    def built_location
      [ "DslLocation", @name, { "description" => @description, "everies" => @everies } ]
    end
  end

  class DslArea < StateItem
    def intentions_for_next_step(options = {})
      # Nothing currently
      nil
    end
  end

  class DslLocation < StateItem
    def initialize(name, engine)
      super
    end

    def state
      @engine.state_for_item(@name)
    end

    def self.register_actions_by_item_and_action_name(act)
      @actions ||= {}
      act.each do |item_name, act_hash|
        if @actions[item_name]
          dup_keys = @actions[item_name].keys | act_hash.keys
          raise "Duplicate item actions for #{item_name.inspect}! List: #{dup_keys.inspect}" unless dup_keys.empty?
          @actions[item_name].merge!(act_hash)
        else
          @actions[item_name] = act_hash
        end
      end
    end

    def self.action_for_item(item_name, action_name)
      @actions[item_name][action_name]
    end

    def intentions_for_next_step(options = {})
      everies = @engine.state_for_property(@name, "everies")
      return [] if everies.empty?
      EveryXTicksIntention.new(@name)
    end

    def run_action(action_name)
      block = DslLocation.action_for_item(@name, action_name)
      raise "No such action as #{action_name.inspect} for #{@name.inspect}!" unless block
      @block_runner ||= DslLocationBlockRunner.new(self)
      @block_runner.instance_eval(&block)
      nil
    end
  end

  class DslLocationBlockRunner
    def initialize(location)
      @location = location
    end

    def state
      @state_wrapper ||= DslLocationStateWrapper.new(@location)
    end

    def action(*args)
      STDERR.puts "Not yet using action: #{args.inspect}"
    end
  end

  class DslLocationStateWrapper
    def initialize(location)
      @location = location
    end

    def method_missing(method_name, *args, &block)
      if method_name.to_s[-1] == "="
        getter_name = method_name.to_s[0..-2]
        setter_name = method_name.to_s
      else
        getter_name = method_name.to_s
        setter_name = method_name.to_s + "="
      end

      STDERR.puts "Method missing: #{method_name.inspect} / #{getter_name.inspect} / #{setter_name.inspect} / #{@location.state.inspect}"
      if @location.state.has_key?(getter_name)
        self.class.define_method(getter_name) do
          @location.state[getter_name]
        end
        self.class.define_method(setter_name) do |val|
          @location.state[setter_name] = val
        end

        # Call to new defined method
        return self.send(method_name, *args, &block)
      end

      # Nope, no matching state.
      STDERR.puts "No such state key as #{method_name.inspect} in DslLocationStateWrapper#method_missing!"
      super
    end

    def respond_to_missing?(method_name, include_private = false)
      @location.state.has_key?(method_name.to_s) || super
    end
  end

  class EveryXTicksIntention < Intention
    def initialize(name)
      @name = name
    end

    def allowed?(engine, options)
      true
    end

    def apply(engine, options)
      everies = engine.state_for_property(@name, "everies")
      everies.each do |every|
        every["counter"] += 1
        if every["counter"] >= every["every"]
          STDERR.puts "Time to execute action #{every["action"].inspect} on item #{@name.inspect} (every #{every["every"]} ticks)!"
          item = engine.item_by_name(@name)
          item.run_action(every["action"])
          every["counter"] = 0
        end
      end
    end
  end
end
