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
  end

  class DslLocation < StateItem
  end

end
