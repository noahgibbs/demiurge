module Demiurge
  # A Demiurge::ActionItem keeps track of actions from Ruby code
  # blocks and implements the Demiurge DSL for action code, including
  # inside World Files.
  #
  # @since 0.0.1
  class ActionItem < StateItem
    # Constructor. Set up ActionItem-specific things like EveryXTicks actions.
    #
    # @param name [String] The registered StateItem name
    # @param engine [Demiurge::Engine] The Engine this item is part of
    # @param state [Hash] The state hash for this item
    # @return [void]
    # @since 0.0.1
    def initialize(name, engine, state)
      super # Set @name and @engine and @state
      @every_x_ticks_intention = ActionItemInternal::EveryXTicksIntention.new(engine, name)
      nil
    end

    # Callback to be called from the Engine when all items are loaded.
    #
    # @return [void]
    # @since 0.0.1
    def finished_init
      loc = self.location
      loc.move_item_inside(self) unless loc.nil?
    end

    # Get the name of this item's location. This is compatible with
    # complex positions, and removes any sub-location suffix, if there
    # is one.
    #
    # @return [String, nil] The location name where this item exists, or nil if it has no location
    # @since 0.0.1
    def location_name
      pos = @state["position"]
      pos ? pos.split("#",2)[0] : nil
    end

    # Get the location StateItem where this item is located.
    #
    # @return [Demiurge::StateItem, nil] The location's StateItem, or nil if this item has no location
    # @since 0.0.1
    def location
      ln = location_name
      return nil if ln == "" || ln == nil
      @engine.item_by_name(location_name)
    end

    # A Position can be simply a location ("here's a room-type object
    # and you're in it") or something more specific, such as a
    # specific coordinate within a room. In general, a Position
    # consists of a location's unique item name, optionally followed
    # by an optional pound sign ("#") and zone-specific additional
    # coordinates.
    #
    # @return [String, nil] This item's position, or nil if it has no location.
    def position
      @state["position"]
    end

    # Get the StateItem of the Zone where this item is located. This
    # may be different from its "home" Zone.
    #
    # @return [StateItem, nil] This item's Zone's StateItem, or nil in the very unusual case that it has no current Zone.
    def zone
      zn = zone_name
      zn ? @engine.item_by_name(zn) : nil
    end

    # Get the Zone name for this StateItem's current location, which
    # may be different from its "home" Zone.
    #
    # @return [String, nil] This item's Zone's name, or nil in the very unusual case that it has no current Zone.
    def zone_name
      l = location
      l ? l.zone_name : state["zone"]
    end

    # An internal function that provides the object's internal state
    # to an action block via a Runner class.
    #
    # @return [Hash] The internal state of this item for use in DSL action blocks
    # @api private
    # @since 0.0.1
    def __state_internal
      @state
    end

    # Get this item's intentions for the next tick.
    #
    # @return [Array<Demiurge::Intention>] An array of intentions for next tick
    # @since 0.0.1
    def intentions_for_next_step
      everies = @state["everies"]
      return [] if everies.nil? || everies.empty?
      [@every_x_ticks_intention]
    end

    # Legal keys to pass to ActionItem#register_actions' hash
    # @since 0.0.1
    ACTION_LEGAL_KEYS = [ "name", "block", "busy", "engine_code", "tags" ]

    # This method is called by (among other things) define_action to
    # specify things about an action.  It's how to specify the
    # action's code, how busy it makes an agent when it occurs, what
    # Runner to use with it, and any appropriate String tags. While it
    # can be called multiple times to specify different things about a
    # single action, it must not be called with the same information.
    # So the block can only be specified once, "busy" can only be
    # specified once and so on.
    #
    # This means that if an action's block is given implicitly by
    # something like an every_X_ticks declaration, it can use
    # define_action to set "busy" or "engine_code". But it can't
    # define a different block of code to run with define_action.
    #
    # @param action_hash [Hash] Specify something or everything about an action by its name.
    # @option action_hash [String] name The name of the action, which is required.
    # @option action_hash [Proc] block The block of code for the action itself
    # @return void
    # @since 0.0.1
    def register_actions(action_hash)
      @engine.register_actions_by_item_and_action_name(@name => action_hash)
    end

    # This is a raw, low-level way to execute an action of an
    # ActionItem. It doesn't wait for Intentions.  It doesn't send
    # extra notifications. It doesn't offer or give a chance to cancel
    # the action.  It just runs.
    #
    # @param action_name [String] The name of the action to run. Must already be registered.
    # @param args [Array] Additional arguments to pass to the action's code block
    # @param current_intention [nil, Intention] Current intention being executed, if any. This is used for to cancel an intention, if necessary
    # @return [void]
    # @since 0.0.1
    def run_action(action_name, *args, current_intention: nil)
      action = get_action(action_name)
      raise ::Demiurge::Errors::NoSuchActionError.new("No such action as #{action_name.inspect} for #{@name.inspect}!",
                                                      "item" => self.name, "action" => action_name) unless action
      block = action["block"]
      raise ::Demiurge::Errors::NoSuchActionError.new("Action was never defined for #{action_name.inspect} of object #{@name.inspect}!",
                                                      "item" => self.name, "action" => action_name) unless block

      runner_constructor_args = {}
      if action["engine_code"]
        block_runner_type = ActionItemInternal::EngineBlockRunner
      elsif self.agent?
        block_runner_type = ActionItemInternal::AgentBlockRunner
        runner_constructor_args[:current_intention] = current_intention
      else
        block_runner_type = ActionItemInternal::ActionItemBlockRunner
        runner_constructor_args[:current_intention] = current_intention
      end
      # TODO: can we save block runners between actions?
      block_runner = block_runner_type.new(self, **runner_constructor_args)
      begin
        block_runner.instance_exec(*args, &block)
      rescue
        #STDERR.puts "#{$!.message}\n#{$!.backtrace.join("\n")}"
        raise ::Demiurge::Errors::BadScriptError.new("Script error of type #{$!.class} with message: #{$!.message}",
                                                     "runner type": block_runner_type.to_s, "action" => action_name);
      end
      nil
    end

    # Get the action hash structure for a given action name. This is
    # normally done to verify that a specific action name exists at
    # all.
    #
    # @param action_name [String] The action name to query
    # @return [Hash, nil] A hash of information about the action, or nil if the action doesn't exist
    # @since 0.0.1
    def get_action(action_name)
      action = @engine.action_for_item(@name, action_name)
      if !action && state["parent"]
        # Do we have a parent and no action definition yet? If so, defer to the parent.
        action = @engine.item_by_name(state["parent"]).get_action(action_name)
      end
      action
    end

    # Return all actions which have the given String tags specified for them.
    #
    # @param tags [Array<String>] An array of tags the returned actions should match
    # @return [Array<Hash>] An array of action structures. The "name" field of each gives the action name
    # @since 0.0.1
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

  # This module is for Intentions, BlockRunners and whatnot that are
  # internal implementation details of ActionItem.
  #
  # @api private
  # @since 0.0.1
  module ActionItemInternal; end

  # BlockRunners set up the environment for an action's block of code.
  # They provide available information and available actions. The
  # BlockRunner parent class is mostly to provide a root location to
  # begin looking for BlockRunners.
  #
  # @since 0.0.1
  class ActionItemInternal::BlockRunner
    # @return [Demiurge::ActionItem] The item the BlockRunner is attached to
    attr_reader :item

    # @return [Demiurge::Engine] The engine the BlockRunner is attached to
    attr_reader :engine

    # Constructor: set the item
    # Ruby bug: with no unused kw args, passing this an empty hash of kw args will give "ArgumentError: wrong number of arguments"
    #
    # @param item [Demiurge::ActionItem] The item using the block, and (usually) the item taking action
    def initialize(item, unused_kw_arg:nil)
      @item = item
      @engine = item.engine
    end
  end

  # This is a very simple BlockRunner for defining DSL actions that
  # need very little extra support. It's for weird, powerful actions
  # that mess with the internals of the engine. You can request it by
  # passing the "engine_code" option to define_action.
  #
  # @since 0.0.1
  class ActionItemInternal::EngineBlockRunner < ActionItemInternal::BlockRunner
  end

  # The ActionItemBlockRunner is a good, general-purpose block runner
  # that supplies more context and more "gentle" object accessors to
  # the block code. The methods of this class are generally intended
  # to be used in the block code.
  #
  # @since 0.0.1
  class ActionItemInternal::ActionItemBlockRunner < ActionItemInternal::BlockRunner
    # @return [Demiurge::Intention, nil] The current intention, if any
    # @since 0.0.1
    attr_reader :current_intention

    # The constructor
    #
    # @param item The item receiving the block and (usually) taking action
    # @param current_intention The current intention, if any; used for canceling
    # @since 0.0.1
    def initialize(item, current_intention:)
      super(item)
      @current_intention = current_intention
    end

    # Access the item's state via a state wrapper. This only allows
    # setting new fields or reading fields that already exist.
    #
    # @return [Demiurge::ActionItemStateWrapper] The state wrapper to control access
    # @since 0.0.1
    def state
      @state_wrapper ||= ActionItemInternal::ActionItemStateWrapper.new(@item)
    end

    private
    def to_demiurge_name(item)
      return item if item.is_a?(String)
      return item.name if item.respond_to?(:name)
      raise "Not sure how to convert PORO to Demiurge name: #{item.inspect}!"
    end
    public

    # Send a notification, starting from the location of the
    # ActionItem. Any fields other than the special "type", "zone",
    # "location" and "actor" fields will be sent as additional
    # notification fields.
    #
    # @param data [Hash] The fields for the notification to send
    # @option data [String] type The notification type to send
    # @option data [String] zone The zone name to send the notification in; defaults to ActionItem's zone
    # @option data [String] location The location name to send the notification in; defaults to ActionItem's location
    # @option data [String] actor The acting item's name; defaults to this ActionItem
    # @return [void]
    # @since 0.0.1
    def notification(data)
      type = data.delete("type") || data.delete(:type) || data.delete("type") || data.delete(:type)
      zone = to_demiurge_name(data.delete("zone") || data.delete(:zone) || @item.zone)
      location = to_demiurge_name(data.delete("location") || data.delete(:location) || @item.location)
      actor = to_demiurge_name(data.delete("actor") || data.delete(:actor) || @item)
      @item.engine.send_notification(data, type: type.to_s, zone: zone, location: location, actor: actor)
      nil
    end

    # Create an action to be executed immediately. This doesn't go
    # through an agent's action queue or make anybody busy. It just
    # happens during the current tick, but it uses the normal
    # allow/offer/execute/notify cycle.
    #
    # @param name [String] The action name
    # @param args [Array] Additional arguments to send to the action
    # @return [void]
    # @since 0.0.1
    def action(name, *args)
      intention = ActionItemInternal::ActionIntention.new(engine, @item.name, name, *args)
      @item.engine.queue_intention(intention)
      nil
    end

    # For tiled maps, cut the position string apart into a location
    # and X and Y tile coordinates within that location.
    #
    # @param position [String] The position string
    # @return [String, Integer, Integer] The location string, the X coordinate and the Y coordinate
    # @since 0.0.1
    def position_to_location_and_tile_coords(position)
      ::Demiurge::TmxLocation.position_to_loc_coords(position)
    end

    # Cancel the current intention. Raise a NoCurrentIntentionError if there isn't one.
    #
    # @param reason [String] The reason to cancel
    # @param extra_info [Hash] Additional cancellation info, if any
    # @return [void]
    # @since 0.0.1
    def cancel_intention(reason, extra_info = {})
      raise ::Demiurge::Errors::NoCurrentIntentionError.new("No current intention in action of item #{@item.name}!", "script_item": @item.name) unless @current_intention
      @current_intention.cancel(reason, extra_info)
      nil
    end

    # Cancel the current intention. Do nothing if there isn't one.
    #
    # @param reason [String] The reason to cancel
    # @param extra_info [Hash] Additional cancellation info, if any
    # @return [void]
    # @since 0.0.1
    def cancel_intention_if_present(reason, extra_info = {})
      @current_intention.cancel(reason, extra_info) if @current_intention
    end
  end

  # This is a BlockRunner for an agent's actions - it will be used if
  # "engine_code" isn't set and the item for the action is an agent.
  #
  # @since 0.0.1
  class ActionItemInternal::AgentBlockRunner < ActionItemInternal::ActionItemBlockRunner
    # Move the agent to a specific position immediately. Don't play a
    # walking animation or anything. Just put it where it needs to be.
    #
    # @param position [String] The position to move to
    # @return [void]
    # @since 0.0.1
    def move_to_instant(position)
      # TODO: We don't have a great way to do this for non-agent entities. How does "accomodate" work for non-agents?
      # This may be app-specific.

      loc_name, next_x, next_y = TmxLocation.position_to_loc_coords(position)
      location = @item.engine.item_by_name(loc_name)
      if !location
        cancel_intention_if_present "Location #{loc_name.inspect} doesn't exist.", "position" => position, "mover" => @item.name
      elsif location.can_accomodate_agent?(@item, position)
        @item.move_to_position(position)
      else
        cancel_intention_if_present "That position is blocked.", "position" => position, "message" => "position blocked", "mover" => @item.name
      end
    end

    # Queue an action for this agent, to be performed during the next
    # tick.
    #
    # @param action_name [String] The action name to queue up
    # @param args [Array] Additional arguments to pass to the action block
    # @return [void]
    # @since 0.0.1
    def queue_action(action_name, *args)
      unless @item.is_a?(::Demiurge::Agent)
        @engine.admin_warning("Trying to queue an action #{action_name.inspect} for an item #{@item.name.inspect} that isn't an agent! Skipping.")
        return
      end
      act = @item.get_action(action_name)
      unless act
        raise Demiurge::Errors::NoSuchActionError.new("Trying to queue an action #{action_name.inspect} for an item #{@item.name.inspect} that doesn't have it!",
                                                      "item" => @item.name, "action" => action_name)
        return
      end
      @item.queue_action(action_name, args)
    end

    # Dump the engine's state as JSON, as an admin-only action.
    #
    # @param filename [String] The filename to dump state to.
    # @return [void]
    # @since 0.0.1
    def dump_state(filename = "statedump.json")
      unless @item.state["admin"] # Admin-only command
        cancel_intention_if_present("The dump_state operation is admin-only!")
        return
      end

      ss = @item.engine.structured_state
      File.open(filename) do |f|
        f.print MultiJson.dump(ss, :pretty => true)
      end
      nil
    end
  end

  # An Intention for an ActionItem to perform one of its actions. This
  # isn't an agent-specific intention which checks if the agent is
  # busy and performs the action exclusively. Instead, it's an
  # ActionItem performing this action as soon as the next tick happens
  # - more than one can occur, for instance.
  #
  # @since 0.0.1
  class ActionItemInternal::ActionIntention < Demiurge::Intention
    # @return [String] The action name to perform
    # @since 0.0.1
    attr :action_name

    # @return [Array] Additional arguments to pass to the argument's code block
    # @since 0.0.1
    attr :action_args

    # Constructor. Pass in the engine, item name, action name and additional arguments.
    #
    # @param engine [Demiurge::Engine] The engine this Intention operates within
    # @param name [String] The item name of the ActionItem acting
    # @param action_name [String] The action name to perform
    # @param args [Array] Additional arguments to pass to the code block
    # @return [void]
    # @since 0.0.1
    def initialize(engine, name, action_name, *args)
      @name = name
      @item = engine.item_by_name(name)
      @action_name = action_name
      @action_args = args
      super(engine)
      nil
    end

    # For now, ActionIntentions don't have a way to specify "allowed"
    # blocks in their DSL, so they are always considered "allowed".
    #
    # return [void]
    # @since 0.0.1
    def allowed?
      true
    end

    # Make an offer of this ActionIntention and see if it is cancelled
    # or modified.  By default, offers are coordinated through the
    # item's location.
    #
    # @param intention_id [Integer] The intention ID assigned to this Intention
    # return [void]
    # @since 0.0.1
    def offer(intention_id)
      loc = @item.location || @item.zone
      loc.receive_offer(@action_name, self, intention_id)
    end

    # Apply the ActionIntention's effects to the appropriate StateItems.
    #
    # return [void]
    # @since 0.0.1
    def apply
      @item.run_action(@action_name, *@action_args, current_intention: self)
    end

    # Send out a notification to indicate this ActionIntention was
    # cancelled.  If "silent" is set to true in the cancellation info,
    # no notification will be sent.
    #
    # @return [void]
    # @since 0.0.1
    def cancel_notification
      # "Silent" notifications are things like an agent's action queue
      # being empty so it cancels its intention.  These are normal
      # operation and nobody is likely to need notification every
      # tick that they didn't ask to do anything so they didn't.
      return if @cancelled_info && @cancelled_info["silent"]
      @engine.send_notification({
                                  reason: @cancelled_reason,
                                  by: @cancelled_by,
                                  id: @intention_id,
                                  intention_type: self.class.to_s,
                                  info: @cancelled_info,
                                },
                                type: "intention_cancelled",
                                zone: @item.zone_name,
                                location: @item.location_name,
                                actor: @item.name)
      nil
    end
  end

  # This class acts to wrap item state to avoid reading fields that
  # haven't been set. Later, it may prevent access to protected state
  # from lower-privilege code.  Though it should always be kept in
  # mind that no World File DSL code is actually secure. At best,
  # security in this API may prevent accidents by the
  # well-intentioned.
  #
  # @api private
  # @since 0.0.1
  class ActionItemInternal::ActionItemStateWrapper
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
      raise ::Demiurge::Errors::NoSuchStateKeyError.new("No such state key as #{method_name.inspect}", "method" => method_name, "item" => @item.name)
      super
    end

    def respond_to_missing?(method_name, include_private = false)
      @item.state.has_key?(method_name.to_s) || super
    end
  end

  # This is a simple Intention that performs a particular action every
  # so many ticks. It expects its state to be set up via the DSL
  # Builder classes.
  #
  # @since 0.0.1
  class ActionItemInternal::EveryXTicksIntention < Intention
    def initialize(engine, name)
      @name = name
      super(engine)
    end

    def allowed?
      true
    end

    # For now, empty. Later we'll want it to honor
    # the offer setting of the underlying action.
    def offer(intention_id)
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

    def apply
      item = @engine.item_by_name(@name)
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
