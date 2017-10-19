module Demiurge
  # A Demiurge::ActionItem keeps track of actions from Ruby code
  # blocks and implements the Demiurge block DSL.
  class ActionItem < StateItem
    attr_reader :engine

    def initialize(name, engine)
      super # Set @name and @engine
    end

    def location_name
      @engine.state_for_property(@name, "location")
    end

    def location
      @engine.item_by_name(location_name)
    end

    def zone
      location.zone
    end

    def zone_name
      location.zone_name
    end

    def __state_internal
      @engine.state_for_item(@name)
    end

    def intentions_for_next_step(options = {})
      everies = @engine.state_for_property(@name, "everies")
      return [] if everies.nil? || everies.empty?
      EveryXTicksIntention.new(@name)
    end

    def run_action(action_name)
      block = @engine.action_for_item(@name, action_name)
      raise "No such action as #{action_name.inspect} for #{@name.inspect}!" unless block
      @block_runner ||= ActionItemBlockRunner.new(self)
      @block_runner.instance_eval(&block)
      nil
    end
  end

  class ActionItemBlockRunner
    def initialize(item)
      @item = item
    end

    def state
      @state_wrapper ||= ActionItemStateWrapper.new(@item)
    end

    def notification(data, notification_type: :sound, zone: @item.zone, location: @item.location, item_acting: @item)
      STDERR.puts "Testing notification of type #{notification_type.inspect}"
      @item.engine.send_notification(notification_type: notification_type.to_s, zone: zone, location: location, item_acting: item_acting)
    end
  end

  class ActionItemStateWrapper
    def initialize(item)
      @item = item
    end

    def has_key?(key)
      @item.__state_internal.has_key?(key)
    end

    def method_missing(method_name, *args, &block)
      if method_name.to_s[-1] == "="
        getter_name = method_name.to_s[0..-2]
        setter_name = method_name.to_s
      else
        getter_name = method_name.to_s
        setter_name = method_name.to_s + "="
      end

      if @item.state.has_key?(getter_name) || method_name.to_s[-1] == "="
        self.class.send(:define_method, getter_name) do
          @item.__state_internal[getter_name]
        end
        self.class.send(:define_method, setter_name) do |val|
          @item.__state_internal[getter_name] = val
        end

        # Call to new defined method
        return self.send(method_name, *args, &block)
      end

      # Nope, no matching state.
      STDERR.puts "No such state key as #{method_name.inspect} in ActionItemStateWrapper#method_missing!"
      super
    end

    def respond_to_missing?(method_name, include_private = false)
      @item.state.has_key?(method_name.to_s) || super
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
          item = engine.item_by_name(@name)
          item.run_action(every["action"])
          every["counter"] = 0
        end
      end
    end
  end
end
