require_relative "../demiurge"

module Demiurge
  # This is a primary method for creating a new Demiurge Engine. It
  # should be passed a list of filenames to load World File DSL
  # from. It will return a fully-configured Engine which has called
  # finished_init. If the Engine should load from an existing
  # state-dump, that can be accomplished via load_state_from_dump.
  #
  # @param filenames [Array<String>] An array of filenames, suitable for calling File.read on
  # @return [Demiurge::Engine] A configured Engine
  # @since 0.0.1
  def self.engine_from_dsl_files(*filenames)
    filename_string_pairs = filenames.map { |fn| [fn, File.read(fn)] }
    engine_from_dsl_text(*filename_string_pairs)
  end

  # This method takes either strings containing World File DSL text,
  # or name/string pairs. If a pair is supplied, the name gives the
  # origin of the text for error messages.
  #
  # @param specs [Array<String>, Array<Array<String>>] Either an array of chunks of DSL text, or an Array of two-element Arrays. Each two-element Array is a String name followed by a String of DSL text
  # @return [Demiurge::Engine] A configured Engine
  # @since 0.0.1
  def self.engine_from_dsl_text(*specs)
    builder = Demiurge::DSL::TopLevelBuilder.new

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
end

module Demiurge::DSL
  # This is the Builder class for the World File DSL.
  class ActionItemBuilder
    attr_reader :built_item

    def check_options(hash, legal_options)
      illegal_options = hash.keys - legal_options
      raise "Illegal options #{illegal_options.inspect} passed to #{caller(1, 3).inspect}!" unless illegal_options.empty?
    end

    LEGAL_OPTIONS = [ "state", "type", "no_build" ]
    def initialize(name, engine, options = {})
      check_options(options, LEGAL_OPTIONS)
      @name = name
      @engine = engine
      @state = options["state"] || {}
      @position = nil
      @display = nil # This is display-specific information that gets passed to the display library

      unless options["type"]
        raise "You must pass a type when initializing a builder!"
      end
      unless options["no_build"]
        @built_item = ::Demiurge::StateItem.from_name_type(@engine, options["type"], @name, @state)
        @engine.register_state_item(@built_item)
      end
    end

    def __state_internal
      @built_item.state
    end

    def state
      @wrapper ||= ::Demiurge::ActionItemStateWrapper.new(self)
    end

    # This all happens at DSL builder time, so we can't directly
    # register an action yet - the item doesn't exist in the engine.
    # But we can make sure the registered block and settings don't
    # conflict within the builder.
    def register_built_action(action)
      raise("Must specify a string 'name' to register_build_action! Only gave #{action.inspect}!") unless action["name"]
      check_options(action, ::Demiurge::ActionItem::ACTION_LEGAL_KEYS)
      @built_item.register_actions(action["name"] => action)
    end

    def every_X_ticks(action_name, t, &block)
      raise("Must provide a positive number for how many ticks, not #{t.inspect}!") unless t.is_a?(Numeric) && t >= 0.0
      @built_item.state["everies"] ||= []
      @built_item.state["everies"] << { "action" => action_name, "every" => t, "counter" => 0 }
      @built_item.register_actions(action_name => { "name" => action_name, "block" => block })
    end

    def position(pos)
      @built_item.state["position"] = pos
    end

    def display(&block)
      # Need to figure out how to pass this through to the Display
      # library.  By design, the simulation/state part of Demiurge
      # ignores this completely.
      @built_item.register_actions("$display" => { "name" => "$display", "block" => block })
    end

    # This catches notifications of the appropriate type and runs the corresponding action.
    def on(event, action_name, options = {}, &block)
      @built_item.state["on_handlers"] ||= {}
      @built_item.state["on_handlers"][event] = action_name
      register_built_action("name" => action_name, "block" => block)

      location = options[:location] || options["location"] || @built_item.location
      zone = options[:zone] || options["zone"] || location.zone_name || @built_item.state["zone"]
      item = options[:actor] || options["actor"] || options[:actor] || options["actor"] || :all

      @engine.subscribe_to_notifications type: event, zone: zone, location: location, actor: item do |notification|
        # To keep this statedump-safe, need to look up the item again
        # every time. @built_item isn't guaranteed to last.
        @engine.item_by_name(@name).run_action(action_name, notification)
      end
    end

    def on_action(caught_action, action_to_run, options = {}, &block)
      @built_item.state["on_action_handlers"] ||= {}
      raise "Already have an on_action (offer) handler for action #{caught_action}! Failing!" if @built_item.state["on_action_handlers"][caught_action]
      @built_item.state["on_action_handlers"][caught_action] = action_to_run
      register_built_action("name" => action_to_run, "block" => block)
    end

    def define_action(action_name, options = {}, &block)
      legal_options = [ "busy", "engine_code", "tags" ]
      illegal_keys = options.keys - legal_options
      raise("Illegal keys #{illegal_keys.inspect} passed to define_action of #{action_name.inspect}!") unless illegal_keys.empty?;
      register_built_action({ "name" => action_name, "block" => block }.merge(options))
    end
  end

  # This is the top-level DSL Builder class, for parsing the top syntactic level of the World Files.
  class TopLevelBuilder
    # This is the private structure of type names that are registered with the Demiurge World File DSL
    @@types = {}

    # Constructor for a new set of World Files and their top-level state.
    def initialize(options = {})
      @zones = []
      @engine = options["engine"] || ::Demiurge::Engine.new(types: @@types, state: [])
    end

    # For now, this just declares an InertStateItem for a given name.
    # It doesn't change the behavior at all. It just keeps that item
    # name from being "orphaned" state that doesn't correspond to any
    # state item.
    #
    # Later, this may be a way to describe how important or transitory
    # state is - is it reset like a zone? Completely transient?
    # Cleared per reboot?
    def inert(item_name, options = {})
      zone_name = options["zone"] || "admin"
      state = options["state"] || {}
      inert_item = ::Demiurge::StateItem.from_name_type(@engine, options["type"] || "InertStateItem", item_name, state.merge("zone" => zone_name))
      @engine.register_state_item(inert_item)
    end

    # Start a new Zone block, using a ZoneBuilder.
    def zone(name, options = {}, &block)
      if @zones.any? { |z| z.name == name }
        # Reopening an existing zone
        builder = ZoneBuilder.new(name, @engine, options.merge("existing" => @zones.detect { |z| z.name == name }))
      else
        builder = ZoneBuilder.new(name, @engine, options)
      end

      builder.instance_eval(&block)
      new_zone = builder.built_item

      @zones |= [ new_zone ] if new_zone  # Add if not already present
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

    # Return the built Engine, but first call the .finished_init
    # callback. This will make sure that cached and duplicated data
    # structures are properly filled in.
    def built_engine
      @engine.finished_init
      @engine
    end
  end

  # Declare an "agent" block in the World File DSL.
  class AgentBuilder < ActionItemBuilder
    def initialize(name, engine, options = {})
      options = { "type" => "Agent" }.merge(options)
      super(name, engine, options)
    end
  end

  # Declare a "zone" block in the World File DSL.
  class ZoneBuilder < ActionItemBuilder
    # Constructor. See if this zone name already exists, and either
    # create a new zone or append to the old one.
    def initialize(name, engine, options = {})
      @existing = options.delete("existing")
      if @existing
        old_type = @existing.state_type
        new_type = options["type"]
        if new_type && old_type != new_type
          raise("Can't reopen zone with type #{(options["type"] || "Unspecified").inspect} after creating with type #{old_type.inspect}!")
        end
        options["no_build"] = true
        @built_item = @existing
      end
      super(name, engine, options.merge("type" => options["type"] || "Zone"))
      @locations = []
      @agents = []
    end

    # Declare a location in this zone.
    def location(name, options = {}, &block)
      state = { "zone" => @name }.merge(options)
      builder = LocationBuilder.new(name, @engine, "type" => options["type"] || "Location", "state" => state)
      builder.instance_eval(&block)
      @built_item.state["contents"] << name
      nil
    end

    # Declare an agent in this zone. If the agent doesn't get a
    # location declaration, by default the agent will usually be
    # invisible (not an interactable location) but will be
    # instantiable as a parent.
    def agent(name, options = {}, &block)
      state = { "zone" => @name }.merge(options)
      builder = AgentBuilder.new(name, @engine, "type" => options["type"] || "Agent", "state" => state)
      builder.instance_eval(&block)
      @built_item.state["contents"] << name
      nil
    end
  end

  # Declare a "location" block in a World File.
  class LocationBuilder < ActionItemBuilder
    # Constructor for a "location" DSL block
    def initialize(name, engine, options = {})
      options["type"] ||= "Location"
      super
      @agents = []
    end

    # Declare a description for this location.
    def description(d)
      @state["description"] = d
    end

    # Declare an agent in this location.
    def agent(name, options = {}, &block)
      state = { "position" => @name, "zone" => @state["zone"] }
      builder = AgentBuilder.new(name, @engine, options.merge("state" => state) )
      builder.instance_eval(&block)
      @built_item.state["contents"] << name
      nil
    end
  end

end

Demiurge::DSL::TopLevelBuilder.register_type "ActionItem", Demiurge::ActionItem
Demiurge::DSL::TopLevelBuilder.register_type "InertStateItem", Demiurge::InertStateItem
Demiurge::DSL::TopLevelBuilder.register_type "Zone", Demiurge::Zone
Demiurge::DSL::TopLevelBuilder.register_type "Location", Demiurge::Location
Demiurge::DSL::TopLevelBuilder.register_type "Agent", Demiurge::Agent
Demiurge::DSL::TopLevelBuilder.register_type "WanderingAgent", Demiurge::WanderingAgent
