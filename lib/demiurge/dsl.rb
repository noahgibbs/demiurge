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

    def initialize(name, engine)
      @name = name
      @engine = engine
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

    # This all happens at DSL builder time, so we can't directly
    # register an action yet - the item doesn't exist in the engine.
    # But we can make sure the registered block and settings don't
    # conflict within the builder.
    def register_built_action(action)
      raise("Must specify a string 'name' to register_build_action! Only gave #{action.inspect}!") unless action["name"]
      legal_keys = [ "name", "block", "busy" ]
      illegal_keys = action.keys - legal_keys
      raise("Hash with illegal keys #{illegal_keys.inspect} passed to register_built_action!") unless illegal_keys.empty?
      if @actions[action["name"]]
        legal_keys.each do |key|
          existing_val = @actions[action["name"]][key]
          if existing_val && action[key] && existing_val != action[key]
            raise "Can't register a second action #{action["name"].inspect} with conflicting key #{key.inspect} in register_built_action!"
          end
        end
        @actions[action["name"]].merge!(action)
      else
        @actions[action["name"]] = action
      end
    end

    def every_X_ticks(action_name, t, &block)
      raise("Must provide a positive number for how many ticks, not #{t.inspect}!") unless t.is_a?(Numeric) && t >= 0.0
      @state["everies"] ||= []
      @state["everies"] << { "action" => action_name, "every" => t, "counter" => 0 }
      register_built_action("name" => action_name, "block" => block)
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
      register_built_action("name" => "$display", "block" => block)
    end

    def on(event, action_name, &block)
      @state["on_handlers"] ||= {}
      @state["on_handlers"][event] = action_name
      register_built_action("name" => action_name, "block" => block)
    end

    def define_action(action_name, options = {}, &block)
      legal_options = [ "busy" ]
      illegal_keys = options.keys - legal_options
      raise("Illegal keys #{illegal_keys.inspect} passed to define_action of #{action_name.inspect}!") unless illegal_keys.empty?;
      register_built_action({ "name" => action_name, "block" => block }.merge(options))
    end
  end

  class TopLevelBuilder
    @@types = {}

    def initialize
      @zones = []
      @locations = []
      @agents = []
      @extras = []
      @item_names = {}
      @engine = ::Demiurge::Engine.new(types: @@types, state: [])
    end

    # For now, this just declares an InertStateItem for a given name.
    # It doesn't change the behavior at all. It just keeps that item
    # name from being "orphaned" state that doesn't correspond to any
    # state item.
    #
    # Later, this may be a way to describe how important or transitory
    # state is - is it reset like a zone? Completely transient?
    # Cleared per reboot?
    def inert(item_name)
      @extras.push(["InertStateItem", item_name, {}])
    end

    def zone(name, &block)
      if @zones.any? { |z| z.name == name }
        # Reopening an existing zone
        builder = ZoneBuilder.new(name, @engine, "existing" => @zones.detect { |z| z.name == name })
      else
        builder = ZoneBuilder.new(name, @engine)
      end

      builder.instance_eval(&block)
      new_zone = builder.built_zone

      @zones |= [ new_zone ] if new_zone  # Add if not already present
      @locations += builder.built_locations
      @agents += builder.built_agents
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
      (@zones + @locations + @agents + @extras).each { |item| @engine.register_state_item(item) }
      @engine.finished_init
      @engine
    end
  end

  class AgentBuilder < ActionItemBuilder
    def initialize(name, engine, extra_state = {})
      super(name, engine)
      @state.merge!(extra_state)
    end

    def built_agent
      agent = ::Demiurge::StateItem.from_name_type(@engine, @type || "Agent", @name, @state)
      agent.register_actions @actions
      agent
    end
  end

  class ZoneBuilder < ActionItemBuilder
    def initialize(name, engine, options = {})
      super(name, engine)
      @existing = options["existing"]
      @locations = []
      @agents = []
    end

    def location(name, &block)
      builder = LocationBuilder.new(name, @engine)
      builder.instance_eval(&block)
      location = builder.built_location
      location.state["zone"] = @name
      @locations << location
      @agents += builder.built_agents
      nil
    end

    def agent(name, &block)
      builder = AgentBuilder.new(name, @engine)
      builder.instance_eval(&block)
      @agents << builder.built_agent
      nil
    end

    def built_zone
      if @existing
        # Point of order: what do we do if a zone isn't given a type
        # on its first reference, but later is given one? In Ruby, for
        # classes, that's actually disallowed... You *can* repeat the
        # type in each zone-reopen to make sure the first one has it.
        if @type && @type != @existing.state_type
          raise "Zone #{@name.inspect} of type #{@existing.state_type.inspect} cannot be reopened to type #{@type.inspect}!"
        end
        @existing.state["location_names"] += @locations.map { |l| l.name }
        @existing.state["agent_names"] += @agents.map { |a| a.name }
        @existing.state["everies"] ||= []
        @existing.state["everies"] += (@state["everies"] || [])
        @existing.state["on_handlers"] ||= {}
        @existing.state["on_handlers"].merge!(@state["on_handlers"] || {})

        @state.delete("everies") # Delete known keys
        @state.delete("on_handlers") # Delete known keys

        unless @state.keys.empty?
          raise "Don't know how to do zone merge with keys #{@state.keys.inspect}!"
        end
      else
        state = @state.merge("location_names" => @locations.map { |l| l.name }, "agent_names" => @agents.map { |a| a.name })
        zone = ::Demiurge::StateItem.from_name_type(@engine, @type || "Zone", @name, state)
        zone.register_actions @actions
        zone
      end
    end

    def built_locations
      @locations
    end

    def built_agents
      @agents
    end
  end

  class LocationBuilder < ActionItemBuilder
    def initialize(name, engine)
      super
      @agents = []
    end

    def description(d)
      @state["description"] = d
    end

    def agent(name, &block)
      builder = AgentBuilder.new(name, @engine, { "position" => @name } )
      builder.instance_eval(&block)
      agent = builder.built_agent
      @agents << agent
      nil
    end

    def built_location
      # TODO: build the item-less engine first, then pass it into the various subclasses so they can create/instantiate?
      loc = ::Demiurge::StateItem.from_name_type(@engine, @type || "Location", @name, @state)
      loc.register_actions @actions
      loc
    end

    def built_agents
      @agents
    end
  end

end

Demiurge::TopLevelBuilder.register_type "ActionItem", Demiurge::ActionItem
Demiurge::TopLevelBuilder.register_type "InertStateItem", Demiurge::InertStateItem
Demiurge::TopLevelBuilder.register_type "Zone", Demiurge::Zone
Demiurge::TopLevelBuilder.register_type "Location", Demiurge::Location
Demiurge::TopLevelBuilder.register_type "Agent", Demiurge::Agent
Demiurge::TopLevelBuilder.register_type "WanderingAgent", Demiurge::WanderingAgent
