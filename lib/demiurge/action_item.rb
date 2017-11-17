module Demiurge
  # A Demiurge::ActionItem keeps track of actions from Ruby code
  # blocks and implements the Demiurge block DSL.
  class ActionItem < StateItem
    attr_reader :engine

    def initialize(name, engine, state)
      super # Set @name and @engine and @state
      @every_x_ticks_intention = EveryXTicksIntention.new(name)
      @actions = {}
    end

    def finished_init
      loc = self.location
      return if loc.nil?  # This item isn't located anywhere, though it may still have a zone.
      return if loc.zone?
      return loc.move_item_inside(self) if loc.respond_to?(:move_item_inside)
      # Else no clue. Do nothing.
    end

    def location_name
      pos = @state["position"]
      pos ? pos.split("#",2)[0] : nil
    end

    def location
      ln = location_name
      return nil if ln == "" || ln == nil
      @engine.item_by_name(location_name)
    end

    # A Position can be simply a location ("here's a room-type object
    # and you're in it") or something more specific, such as a
    # specific coordinate within a room. In general, a Position
    # consists of a location's unique item name, optionally followed
    # by a pound sign ("#") and zone-specific additional coordinates
    # of some kind.
    def position
      @state["position"]
    end

    def zone
      zn = zone_name
      zn ? @engine.item_by_name(zn) : nil
    end

    def zone_name
      l = location
      l ? l.zone_name : state["zone_name"]
    end

    def __state_internal
      @state
    end

    def intentions_for_next_step(options = {})
      everies = @state["everies"]
      return [] if everies.nil? || everies.empty?
      [@every_x_ticks_intention]
    end

    ACTION_LEGAL_KEYS = [ "name", "block", "busy", "engine_code", "tags" ]
    def register_actions(action_hash)
      @engine.register_actions_by_item_and_action_name(@name => action_hash)
    end

    def run_action(action_name, *args)
      action = get_action(action_name)
      raise "No such action as #{action_name.inspect} for #{@name.inspect}!" unless action
      block = action["block"]
      raise "Action was never defined for #{action_name.inspect} of object #{@name.inspect}!" unless block

      if action["engine_code"]
        block_runner_type = EngineBlockRunner
      elsif self.agent?
        block_runner_type = AgentBlockRunner
      else
        block_runner_type = ActionItemBlockRunner
      end
      # TODO: can we save block runners between actions?
      block_runner = block_runner_type.new(self)
      block_runner.instance_exec(*args, &block)
      nil
    end

    def get_action(action_name)
      action = @engine.action_for_item(@name, action_name)
      if !action && state["parent"]
        # Do we have a parent and no action definition yet? If so, defer to the parent.
        action = @engine.item_by_name(state["parent"]).get_action(action_name)
      end
      action
    end

    def get_actions_with_tags(tags)
      tags = [tags].flatten # Allow calling with a single tag string
      @actions = []
      @engine.actions_for_item(@name).each do |action_name, action_struct|
        # I'm sure there's some more clever way to check if the action contains all these tags...
        if (tags - (action_struct["tags"] || [])).empty?
          @actions.push action_struct
        end
      end
      @actions
    end
  end

  class EngineBlockRunner
    attr_reader :item

    def initialize(item)
      @item = item
    end

    def engine
      @item.engine
    end
  end

  class ActionItemBlockRunner
    attr_reader :item
    attr_reader :engine

    # This is the item receiving the block. It is usually the item taking the action.
    def initialize(item)
      @item = item
      @engine = item.engine
    end

    def state
      @state_wrapper ||= ActionItemStateWrapper.new(@item)
    end

    private
    def to_demiurge_name(item)
      return item if item.is_a?(String)
      return item.name if item.respond_to?(:name)
      raise "Not sure how to convert PORO to Demiurge name: #{item.inspect}!"
    end
    public

    # Methods that can be used in a Demiurge block by default.  At
    # some point, presumably we want to make this much more customized
    # by allowing specific actions for specific ActionItems and so on.

    def notification(data)
      notification_type = data.delete("notification_type") || data.delete(:notification_type) || data.delete("type") || data.delete(:type)
      zone = to_demiurge_name(data.delete("zone") || data.delete(:zone) || @item.zone)
      location = to_demiurge_name(data.delete("location") || data.delete(:location) || @item.location)
      item_acting = to_demiurge_name(data.delete("item_acting") || data.delete(:item_acting) || @item)
      @item.engine.send_notification(data, notification_type: notification_type.to_s, zone: zone, location: location, item_acting: item_acting)
    end

    # Create an action to be executed immediately. This doesn't go
    # through an agent's action queue or make anybody busy. It just
    # happens, with the normal allow/offer/execute/notify cycle.
    def action(name, *args)
      intention = ActionIntention.new(engine, @item.name, name, *args)
      @item.engine.queue_intention(intention)
    end

    def position_to_location_and_tile_coords(position)
      ::Demiurge::TmxLocation.position_to_loc_coords(position)
    end
  end

  class AgentBlockRunner < ActionItemBlockRunner
    def move_to_instant(position)
      # TODO: We don't have a great way to do this for non-agent entities. How does "accomodate" work for non-agents?
      # This may be app-specific.

      # TODO: if we cancel out of this, set a cancellation notice and reason.
      loc_name, next_x, next_y = TmxLocation.position_to_loc_coords(position)
      location = @item.engine.item_by_name(loc_name)
      if location.can_accomodate_agent?(@item, position)
        @item.move_to_position(position)
      end
    end

    def queue_action(action_name, *args)
      unless @item.is_a?(::Demiurge::Agent)
        STDERR.puts "Trying to queue an action #{action_name.inspect} for an item #{@item.name.inspect} that isn't an agent! Skipping."
        return
      end
      act = @item.get_action(action_name)
      unless act
        STDERR.puts "Trying to queue an action #{action_name.inspect} for an item #{@item.name.inspect} that doesn't have it! Skipping."
        return
      end
      @item.queue_action(action_name, args)
    end

    def dump_state(filename = "statedump.json")
      return unless @item.state["admin"] # Admin-only command

      ss = @item.engine.structured_state
      File.open(filename) do |f|
        f.print MultiJson.dump(ss, :pretty => true)
      end
    end
  end

  class ActionIntention < Intention
    attr :action_name
    attr :action_args

    def initialize(engine, name, action_name, *args)
      @engine = engine
      @name = name
      @item = engine.item_by_name(name)
      @action_name = action_name
      @action_args = args
    end

    # For now, actions don't have an option for "allowed" blocks.
    def allowed?(engine, options = {})
      true
    end

    # By default, offers are coordinated through the item's location.
    def offer(engine, intention_id, options = {})
      loc = @item.location || @item.zone
      on_actions = loc.state["on_action_handlers"]
      if on_actions && on_actions[@action_name]
        loc.run_action(on_actions[@action_name], self)
      end
    end

    def apply(engine, options = {})
      @item.run_action(@action_name, *@action_args)
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

    # For now, empty. Later we'll want it to honor
    # the offer setting of the underlying action.
    def offer(engine, intention_id, options)
    end

    def apply(engine, options)
      item = engine.item_by_name(@name)
      everies = item.state["everies"]
      everies.each do |every|
        every["counter"] += 1
        if every["counter"] >= every["every"]
          item.run_action(every["action"])
          every["counter"] = 0
        end
      end
    end
  end
end
