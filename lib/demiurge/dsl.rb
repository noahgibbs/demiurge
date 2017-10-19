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

  class ActionItemBuilder
    attr_reader :actions

    def initialize(name)
      @name = name
      @state = {}
      @actions = {}
    end

    def __state_internal
      @state
    end

    def state
      @wrapper ||= ActionItemStateWrapper.new(self)
    end

    def every_X_ticks(action_name, t, &block)
      @state["everies"] ||= []
      @state["everies"] << { "action" => action_name, "every" => t, "counter" => 0 }
      @actions[action_name] = block
    end

    def on(event, action_name, &block)
      @state["on_handlers"] ||= {}
      @state["on_handlers"][event] = action_name
      @actions[action_name] = block
    end

    def built_actions
      @actions
    end
  end

  class TopLevelBuilder
    @@types = {}

    def initialize
      @zones = []
      @locations = []
      @agents = []
      @item_names = {}
      @item_actions = {}
    end

    def register_new_serialized_objects(objs, actions = nil)
      objs.each_with_index do |obj, index|
        name = obj[1]
        raise "Duplicated object name #{name.inspect}!" if @item_names[name]
        @item_names[name] = true

        @item_actions[name] = actions[index] if actions && actions[index]
      end
      objs
    end

    def zone(name, &block)
      builder = ZoneBuilder.new(name)
      builder.instance_eval(&block)
      new_zone = builder.built_zone
      zone_actions = builder.built_actions

      # Merge with any existing zone with the same name.
      # This allows zone re-opening in multiple Ruby files.
      same_zone = @zones.detect { |z| z[1] == new_zone[1] }
      if same_zone
        array_merged_keys = [ "location_names", "everies" ]
        hash_merged_keys = [ "on_handlers" ]
        new_state_keys = new_zone[2].keys - array_merged_keys - hash_merged_keys
        old_state_keys = same_zone[2].keys - array_merged_keys - hash_merged_keys
        dup_keys = new_state_keys & old_state_keys
        raise("Zone #{new_zone[1].inspect} is reopened and duplicates state keys: #{dup_keys.inspect}!") unless dup_keys.empty?

        array_merged_keys.each do |merged_key_name|
          new_values = new_zone[2][merged_key_name] || []
          old_values = same_zone[2][merged_key_name] || []
          new_zone[2][merged_key_name] = old_values + new_values
        end
        hash_merged_keys.each do |merged_key_name|
          new_values = new_zone[2][merged_key_name] || {}
          old_values = same_zone[2][merged_key_name] || {}
          new_zone[2][merged_key_name] = old_values.merge(new_values)
        end
        same_zone[2].merge!(new_zone[2]) # This will overwrite location names
      else
        @zones << register_new_serialized_objects([new_zone], [zone_actions])[0]
      end

      @locations += register_new_serialized_objects(builder.built_locations, builder.location_actions)
      nil
    end

    def agent(name, &block)
      builder = AgentBuilder.new(name)
      builder.instance_eval(&block)
      agent = builder.built_agent
      actions = builder.built_actions
      @agents << register_new_serialized_objects([agent], [actions])[0]
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
      engine.register_actions_by_item_and_action_name(@item_actions)
      engine
    end
  end

  class AgentBuilder < ActionItemBuilder
    def initialize
    end

    def built_agent
      ["Agent", @name, @state]
    end
  end

  class ZoneBuilder < ActionItemBuilder
    attr_reader :location_actions

    def initialize(name)
      super
      @locations = []
      @location_actions = []
    end

    def location(name, &block)
      builder = LocationBuilder.new(name)
      builder.instance_eval(&block)
      location = builder.built_location
      location[2].merge!("zone" => @name)
      @locations << location
      @location_actions << builder.built_actions
      nil
    end

    def built_zone
      [ "Zone", @name, @state.merge("location_names" => @locations.map { |l| l[1] }) ]
    end

    def built_locations
      @locations
    end
  end

  class LocationBuilder < ActionItemBuilder
    def initialize(name)
      super
    end

    def description(d)
      @state["description"] = d
    end

    def built_location
      [ "Location", @name, @state ]
    end
  end

end

Demiurge::TopLevelBuilder.register_type "Zone", Demiurge::Zone
Demiurge::TopLevelBuilder.register_type "Location", Demiurge::Location
Demiurge::TopLevelBuilder.register_type "Agent", Demiurge::Agent
