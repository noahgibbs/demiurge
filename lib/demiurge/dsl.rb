require_relative "../demiurge"

module Demiurge
  def self.engine_from_dsl_files(*filenames)
    filename_string_pairs = filenames.map { |fn| [fn, File.read(fn)] }
    engine_from_dsl_text(*filename_string_pairs)
  end

  # Note: may supply either strings or filename/string pairs.
  # In the latter case, eval errors will give the filename along
  # with the error.
  def self.engine_from_dsl_text(*specs)
    builder = Demiurge::TopLevelBuilder.new

    specs.each do |spec|
      if spec.is_a?(String)
        builder.instance_eval spec
      elsif spec.is_a?(Array)
        if spec.size != 2
          raise "Not sure what to do with a #{spec.size}-elt array, normally this is a filename/string pair!"
        end
        builder.instance_eval spec[1], spec[0]
      else
        raise "Not sure what to do in engine_from_dsl_text with a #{spec.class}!"
      end
    end

    builder.built_engine
  end

  class TopLevelBuilder
    @@types = {}

    def initialize
      @zones = []
      @locations = []
      @agents = []
    end

    def zone(name, &block)
      builder = ZoneBuilder.new(name)
      builder.instance_eval(&block)
      @zones << builder.built_zone
      @locations += builder.built_locations
      nil
    end

    def agent(name, &block)
      builder = AgentBuilder.new(name)
      builder.instance_eval(&block)
      @agents << builder.built_agent
      nil
    end

    def self.register_type(name, klass)
      if @@types[name.to_s]
        raise("Attempting to re-register type #{name.inspect} with a different class!") unless @@types[name.to_s] == klass
      else
        @@types[name.to_s] = klass
      end
    end

    def built_engine
      state = @zones + @locations + @agents
      engine = ::Demiurge::Engine.new(types: @@types, state: state)
      engine
    end
  end

  class AgentBuilder
    def initialize
    end

    def built_agent
      ["DslAgent", @name]
    end
  end

  class ZoneBuilder
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
      ActionItem.register_actions_by_item_and_action_name(location[1] => builder.actions)
      nil
    end

    def built_zone
      [ "DslZone", @name, "location_names" => @locations.map { |l| l[1] } ]
    end

    def built_locations
      @locations
    end
  end

  class LocationBuilder
    attr_reader :actions

    def initialize(name)
      @name = name
      @actions = {}
      @state = {}
    end

    def description(d)
      @state["description"] = d
    end

    def __state_internal
      @state
    end

    def state
      @wrapper ||= DslItemStateWrapper.new(self)
    end

    def every_X_ticks(action_name, t, &block)
      @state["everies"] ||= []
      @state["everies"] << { "action" => action_name, "every" => t, "counter" => 0 }
      raise("Duplicate item/action combination for action #{action_name.inspect}!") if @actions[action_name]
      @actions[action_name] = block
    end

    def built_location
      [ "DslLocation", @name, @state ]
    end
  end

  class DslZone < Zone
  end

  class DslLocation < ActionItem
  end

  class DslAgent < ActionItem
  end

end

Demiurge::TopLevelBuilder.register_type "DslZone", Demiurge::DslZone
Demiurge::TopLevelBuilder.register_type "DslLocation", Demiurge::DslLocation
Demiurge::TopLevelBuilder.register_type "DslAgent", Demiurge::DslAgent
