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
      @position = nil
      @type = nil  # This is the specific subclass to instantiate
      @display = nil # This is display-specific information that gets passed to the display library
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

    def position(pos)
      @state["position"] = pos
    end

    def type(t)
      @type = t.to_s
    end

    def display(&block)
      # Need to figure out how to pass this through to the Display
      # library.  By design, the simulation/state part of Demiurge
      # ignores this completely.
      @actions["$display"] = block
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

    # This "registers" the serialized objects in the sense that it
    # tracks their names and actions to be added to the Engine when it
    # is created later.
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
        if same_zone[2]["type"] && new_zone[2]["type"] && same_zone[2]["type"] != new_zone[2]["type"]
          raise("A Zone can only have one type! No merging different types #{same_zone[2]["type"]} and #{new_zone[2]["type"]} in the same zone!")
        end

        array_merged_keys = [ "location_names", "agent_names", "everies" ]
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
      @agents += register_new_serialized_objects(builder.built_agents, builder.agent_actions)
      nil
    end

    # It's hard to figure out where and how to register types and
    # plugins for the World File format. By their nature, they need to
    # be in place before an Engine exists, so that's not the right
    # place. If they didn't exist before engines, we'd somehow need to
    # register them with each engine as it was created. Since Engines
    # keep track of that, that's exactly the same problem we're trying
    # to solve, just for the Engine builder. And it seems like
    # "register this plugin with Demiurge World Files" is more of a
    # process-global operation than a per-Engine operation.  So these
    # wind up in awkward spots.
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
      engine.finished_init
      engine
    end
  end

  class AgentBuilder < ActionItemBuilder
    def built_agent
      [@type || "Agent", @name, @state]
    end
  end

  class ZoneBuilder < ActionItemBuilder
    attr_reader :location_actions
    attr_reader :agent_actions

    def initialize(name)
      super
      @locations = []
      @location_actions = []
      @agents = []
      @agent_actions = []
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

    def agent(name, &block)
      builder = AgentBuilder.new(name)
      builder.instance_eval(&block)
      agent = builder.built_agent
      actions = builder.built_actions
      @agents << agent
      @agent_actions << actions
      nil
    end

    def built_zone
      [ @type || "Zone", @name, @state.merge("location_names" => @locations.map { |l| l[1] }, "agent_names" => @agents.map { |a| a[1] }) ]
    end

    def built_locations
      @locations
    end

    def built_agents
      @agents
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
      [ @type || "Location", @name, @state ]
    end
  end

end

Demiurge::TopLevelBuilder.register_type "Zone", Demiurge::Zone
Demiurge::TopLevelBuilder.register_type "Location", Demiurge::Location
Demiurge::TopLevelBuilder.register_type "Agent", Demiurge::Agent
Demiurge::TopLevelBuilder.register_type "WanderingAgent", Demiurge::WanderingAgent
