module Demiurge
  # A Demiurge::ActionItem keeps track of actions from Ruby code
  # blocks and implements the Demiurge block DSL.
  class ActionItem < StateItem
    attr_reader :engine

    def initialize(name, engine, state)
      super # Set @name and @engine and @state
      @every_x_ticks_intention = EveryXTicksIntention.new(engine, name)
      @actions = {}
    end

    def finished_init
      loc = self.location
      loc.move_item_inside(self) unless loc.nil?
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
      l ? l.zone_name : state["zone"]
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

    def run_action(action_name, *args, current_intention: nil)
      action = get_action(action_name)
      raise "No such action as #{action_name.inspect} for #{@name.inspect}!" unless action
      block = action["block"]
      raise "Action was never defined for #{action_name.inspect} of object #{@name.inspect}!" unless block

      runner_constructor_args = {}
      if action["engine_code"]
        block_runner_type = EngineBlockRunner
      elsif self.agent?
        block_runner_type = AgentBlockRunner
        runner_constructor_args[:current_intention] = current_intention
      else
        block_runner_type = ActionItemBlockRunner
        runner_constructor_args[:current_intention] = current_intention
      end
      # TODO: can we save block runners between actions?
      block_runner = block_runner_type.new(self, **runner_constructor_args)
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

    # Ruby bug: with no unused kw args, passing this an empty hash of kw args will give "ArgumentError: wrong number of arguments"
    def initialize(item, unused_kw_arg:nil)
      @item = item
    end

    def engine
      @item.engine
    end
  end

  class ActionItemBlockRunner
    attr_reader :item
    attr_reader :engine
    attr_reader :current_intention

    # This is the item receiving the block. It is usually the item taking the action.
    def initialize(item, current_intention:)
      @item = item
      @engine = item.engine
      @current_intention = current_intention
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
      type = data.delete("type") || data.delete(:type) || data.delete("type") || data.delete(:type)
      zone = to_demiurge_name(data.delete("zone") || data.delete(:zone) || @item.zone)
      location = to_demiurge_name(data.delete("location") || data.delete(:location) || @item.location)
      actor = to_demiurge_name(data.delete("actor") || data.delete(:actor) || @item)
      @item.engine.send_notification(data, type: type.to_s, zone: zone, location: location, actor: actor)
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

    def cancel_intention(reason)
      raise("No current intention!") unless @current_intention
      @current_intention.cancel(reason)
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
      else
        cancel_action "That position is blocked.", "position" => position, "message" => "position blocked", "mover" => @item.name
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
      @name = name
      @item = engine.item_by_name(name)
      @action_name = action_name
      @action_args = args
      super(engine)
    end

    # For now, actions don't have an option for "allowed" blocks.
    def allowed?(engine, options = {})
      true
    end

    # By default, offers are coordinated through the item's location.
    def offer(engine, intention_id, options = {})
      loc = @item.location || @item.zone
      loc.receive_offer(@action_name, self, intention_id)
    end

    def apply(engine, options = {})
      @item.run_action(@action_name, *@action_args, current_intention: self)
    end

    def cancel_notification
      # "Silent" notifications are things like an agent's action queue
      # being empty so it cancels its intention.  These are normal
      # operation and nobody is likely to need notification every
      # tick that they didn't ask to do anything so they didn't.
      return if @cancelled_info && @cancelled_info["silent"]
      @engine.send_notification({ reason: @cancelled_reason, by: @cancelled_by, id: @intention_id, intention_type: self.class.to_s },
        type: "intention_cancelled", zone: @item.zone_name, location: @item.location_name, actor: @item.name)
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
    def initialize(engine, name)
      @name = name
      super(engine)
    end

    def allowed?(engine, options)
      true
    end

    # For now, empty. Later we'll want it to honor
    # the offer setting of the underlying action.
    def offer(engine, intention_id, options)
    end

    # Shouldn't normally happen, but just in case...
    def cancel_notification
      # "Silent" notifications are things like an agent's action queue
      # being empty so it cancels its intention.  These are normal
      # operation and nobody is likely to need notification every
      # tick that they didn't ask to do anything so they didn't.
      return if @cancelled_info && @cancelled_info["silent"]
      item = @engine.item_by_name(@name)
      @engine.send_notification({ reason: @cancelled_reason, by: @cancelled_by, id: @intention_id, intention_type: self.class.to_s },
                                type: "intention_cancelled", zone: item.zone_name, location: item.location_name, actor: item.name)
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
