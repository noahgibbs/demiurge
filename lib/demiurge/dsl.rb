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
    end

    def location(name, &block)
      builder = LocationBuilder.new(name)
      builder.instance_eval(&block)
      @locations << builder.built_location
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
    def initialize(name)
      @name = name
      @everies = []
      @description = nil
    end

    def description(d)
      @description = d
    end

    def every_X_ticks(action_name, t, &block)
      @everies << { "action" => action_name, "every" => t, "counter" => 0 }
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

    def intentions_for_next_step(options = {})
      everies = @engine.state_for_property(@name, "everies")
      return [] if everies.empty?
      intention = EveryXTicksIntention.new(@name)
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
      STDERR.puts "Applying EveryXTicksIntention!"
      everies = engine.state_for_property(@name, "everies")
      everies.each do |every|
        STDERR.puts "Increment counter for object #{@name} action #{every["action"]}..."
        every["counter"] += 1  # TODO: Use set_state_for_property?
        if every["counter"] >= every["every"]
          STDERR.puts "Time to execute action #{every["action"]}!"
          every["counter"] = 0 # TODO: use set_state_for_property?
        end
      end
    end
  end
end
