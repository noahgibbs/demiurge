module Demiurge
  class StateItem; end
  class Intention < StateItem; end

  # A Demiurge::ActionItem keeps track of actions from Ruby code
  # blocks and implements the Demiurge block DSL.
  class ActionItem < StateItem
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
      block = ActionItem.action_for_item(@name, action_name)
      raise "No such action as #{action_name.inspect} for #{@name.inspect}!" unless block
      @block_runner ||= DslItemBlockRunner.new(self)
      @block_runner.instance_eval(&block)
      nil
    end
  end

  class DslItemBlockRunner
    def initialize(item)
      @item = item
    end

    def state
      @state_wrapper ||= DslItemStateWrapper.new(@item)
    end

    def action(*args)
      STDERR.puts "Not yet using action: #{args.inspect}"
    end
  end

  class DslItemStateWrapper
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
      STDERR.puts "No such state key as #{method_name.inspect} in DslItemStateWrapper#method_missing!"
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
          STDERR.puts "Time to execute action #{every["action"].inspect} on item #{@name.inspect} (every #{every["every"]} ticks)!"
          item = engine.item_by_name(@name)
          item.run_action(every["action"])
          every["counter"] = 0
        end
      end
    end
  end
end
