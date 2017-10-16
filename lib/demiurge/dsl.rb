require_relative "../demiurge"

module Demiurge
  def self.engine_from_dsl_files(*filenames)
    filename_string_pairs = filenames.map { |fn| [fn, File.read(fn)] }
    engine_from_dsl_text(filename_string_pairs)
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
    end

    def zone(name, &block)
      builder = ZoneBuilder.new(name)
      builder.instance_eval(&block)
      @zones << builder.built_zone
      @locations += builder.built_locations
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
      state = @zones + @locations
      engine = ::Demiurge::Engine.new(types: @@types, state: state)
      engine
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
      DslLocation.register_actions_by_item_and_action_name(location[1] => builder.actions)
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
      @wrapper ||= DslLocationStateWrapper.new(self)
    end

    def every_X_ticks(action_name, t, &block)
      @state["everies"] ||= []
      @state["everies"] << { "action" => action_name, "every" => t, "counter" => 0 }
      @actions[action_name] = block
    end

    def built_location
      [ "DslLocation", @name, @state ]
    end
  end

  # This is a very simple zone that just passes control to all children when determining intentions.
  class DslZone < Zone
    def intentions_for_next_step(options = {})
      intentions = @engine.state_for_property(@name, "location_names").flat_map do |loc_name|
        @engine.item_by_name(loc_name).intentions_for_next_step
      end
      intentions
    end
  end

  class DslLocation < StateItem
    def initialize(name, engine)
      super # Set @name and @engine
    end

    def __state_internal
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

    def has_key?(key)
      @location.__state_internal.has_key?(key)
    end

    def method_missing(method_name, *args, &block)
      if method_name.to_s[-1] == "="
        getter_name = method_name.to_s[0..-2]
        setter_name = method_name.to_s
      else
        getter_name = method_name.to_s
        setter_name = method_name.to_s + "="
      end

      location = @location

      if location.state.has_key?(getter_name) || method_name.to_s[-1] == "="
        self.class.send(:define_method, getter_name) do
          location.__state_internal[getter_name]
        end
        self.class.send(:define_method, setter_name) do |val|
          location.__state_internal[getter_name] = val
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

Demiurge::TopLevelBuilder.register_type "DslZone", Demiurge::DslZone
Demiurge::TopLevelBuilder.register_type "DslLocation", Demiurge::DslLocation
