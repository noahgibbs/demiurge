module Demiurge

  # Agents correspond roughly to "mobiles" in many games. An agent
  # isn't particularly different from other Demiurge objects, but it's
  # useful to have some helper classes for things like pathfinding.
  # Also, humans expect agents to have some finite ability to perform
  # actions over time, so it's nice to regulate how much an agent can
  # get done and how "busy" it is. This keeps an AI agent from just
  # queueing up 30 move intentions and crossing the room in a single
  # tick, for instance. It does *not* keep that same AI from having an
  # intentional 30-square move that works in a single tick, but it
  # slows the rate of actions. Agents get a single "real" intention,
  # unlike, say, rooms, which can have lots going on at once.
  #
  # @since 0.0.1
  class Agent < ActionItem

    def initialize(*args)
      super
      state["queued_actions"] ||= []
      state["queue_number"] ||= 0
    end

    def finished_init
      super
      @agent_maintenance = AgentInternal::AgentMaintenanceIntention.new(engine, @name)
      state["busy"] ||= 0 # By default, start out idle.
    end

    # An Agent is, indeed, an Agent.
    #
    # @return [Boolean] Return true for Agent and its subclasses.
    # @since 0.0.1
    def agent?
      true
    end

    # This method will move the agent and notify about that change. It
    # doesn't use an intention or an agent's action queue, and it
    # doesn't wait for a tick to happen. It just does it. The method
    # *does* handle exits and generally allows the location to
    # respond.  But it's assumed that the offer cycle, if it needs to
    # happen, has happened already.
    #
    # @param pos [String] A position string to move to
    # @param options [Hash] A hash of how to do the movement; Demiurge doesn't internally use this hash, but your World Files or display library may do so
    # @return [void]
    # @since 0.0.1
    def move_to_position(pos, options = {})
      old_pos = self.position
      old_loc = self.location_name
      old_zone_name = self.zone_name
      expected_new_loc = pos.split("#")[0]

      if old_loc && !self.location
        raise ::Demiurge::Errors::LocationNameNotFoundError.new("Item #{@name.inspect} has an old location name (#{old_loc.inspect}) with no matching location object!",
                                                                { "item_name" => @name, "location_name" => old_loc, "moving_to" => pos },
                                                                execution_context: @engine.execution_context);
      end

      if old_loc != nil && expected_new_loc == old_loc
        self.location.item_change_position(self, old_pos, pos)
      elsif old_loc != nil
        # This also handles zone changes.
        self.location.item_change_location(self, old_pos, pos)
      end
      # We're not guaranteed to wind up where we expected, so get the
      # new location *after* item_change_location or
      # item_change_position.
      new_loc = self.location_name

      @engine.send_notification({ old_position: old_pos, old_location: old_loc, new_position: self.position, new_location: new_loc },
                                  type: Demiurge::Notifications::MoveFrom, zone: old_zone_name, location: old_loc, actor: @name, include_context: true)
      @engine.send_notification({ old_position: old_pos, old_location: old_loc, new_position: self.position, new_location: new_loc, options: options },
                                  type: Demiurge::Notifications::MoveTo, zone: self.zone_name, location: self.location_name, actor: @name, include_context: true)
    end

    # Calculate the agent's intentions for the following tick. These
    # Intentions can potentially trigger other Intentions.
    #
    # @return [Array<Intention>] The Intentions for the (first part of the) following tick.
    # @since 0.0.1
    def intentions_for_next_step
      agent_action = AgentInternal::AgentActionIntention.new(@name, engine)
      super + [@agent_maintenance, agent_action]
    end

    # Queue an action to be run after previous actions are complete,
    # and when the agent is no longer busy from taking them. The
    # action queue entry is assigned a unique-per-agent queue number,
    # which is returned from this action.
    #
    # @param action_name [String] The name of the action to take when possible
    # @param args [Array] Additional arguments to pass to the action's code block
    # @return [Integer] Returns the queue number for this action - note that queue numbers are only unique per-agent
    # @since 0.0.1
    def queue_action(action_name, *args)
      raise ::Demiurge::Errors::NoSuchActionError.new("Not an action: #{action_name.inspect}!", { "action_name" => action_name },
                                                      execution_context: @engine.execution_context) unless get_action(action_name)
      state["queue_number"] += 1
      state["queued_actions"].push([action_name, args, state["queue_number"]])
      state["queue_number"]
    end

    # Any queued actions waiting to occur will be discarded.
    #
    # @return [void]
    # @since 0.0.1
    def clear_intention_queue
      state.delete "queued_actions"
      nil
    end
  end

  # Code objects internal to the Agent implementation
  # @api private
  module AgentInternal; end

  # The AgentMaintenanceIntention reduces the level of "busy"-ness of
  # the agent on each tick.
  # @todo Merge this with the AgentActionIntention used for taking queued actions
  #
  # @api private
  class AgentInternal::AgentMaintenanceIntention < Intention
    # Constructor. Takes an engine and agent name.
    def initialize(engine, name)
      @name = name
      super(engine)
    end

    # Normally, the agent's maintenance intention can't be blocked,
    # cancelled or modified.
    def offer
    end

    # An AgentMaintenanceIntention is always considered to be allowed.
    def allowed?
      true
    end

    # Reduce the amount of busy-ness.
    def apply
      agent = @engine.item_by_name(@name)
      agent.state["busy"] -= 1 if agent.state["busy"] > 0
    end
  end

  # An AgentActionIntention is how the agent takes queued actions each
  # tick.
  #
  # @note There is a bit of weirdness in how this intention handles
  #   {#allowed?} and {#offer}. We want to be able to queue an action
  #   on the same tick that we execute it if the agent is idle. So we
  #   count this intention as #allowed?  even if the queue is empty,
  #   then silent-cancel the intention during {#offer} if nobody has
  #   added anything to it. If you see a lot of cancel notifications
  #   from this object with "silent" set, now you know why.
  #
  # @api private
  class AgentInternal::AgentActionIntention < ActionItemInternal::ActionIntention
    # @return [StateItem] The agent to whom this Intention applies
    attr_reader :agent
    # @return [String] The queued action name this Intention will next take
    attr_reader :action_name

    # Constructor. Takes an agent name and an engine
    def initialize(name, engine)
      super(engine, name, "")
      @agent = engine.item_by_name(name)
      raise ::Demiurge::Errors::NoSuchAgentError.new("No such agent as #{name.inspect} found in AgentActionIntention!", "agent" => name,
                                                     execution_context: engine.execution_context) unless @agent
    end

    # An action being pulled from the action queue is offered normally.
    def offer
      # Don't offer the action if it's going to be a no-op.
      if @agent.state["busy"] > 0
        # See comment on "silent" in #allowed? below.
        self.cancel "Agent #{@name.inspect} was too busy to act (#{@agent.state["busy"]}).", "silent" => "true"
        return
      elsif @agent.state["queued_actions"].empty?
        self.cancel "Agent #{@name.inspect} had no actions during the 'offer' phase.", "silent" => "true"
        return
      end
      # Now offer the agent's action via the usual channels
      action = @agent.state["queued_actions"][0]
      @action_name, @action_args, @action_queue_number = *action
      @action_struct = @agent.get_action(@action_name)
      super
    end

    # This action is allowed if the agent is not busy, or will become not-busy soon
    def allowed?
      # If the agent's busy state will clear this turn, this action
      # could happen.  We intentionally don't send a "disallowed"
      # notification for the action. It's not cancelled, nor is it
      # dispatched successfully. It's just waiting for a later tick to
      # do one of those two things.
      return false if @agent.state["busy"] > 1

      # A dilemma: if we cancel now when no actions are queued, then
      # any action queued this turn (e.g. from an
      # EveryXActionsIntention) won't be executed -- we said this
      # intention wasn't happening. If we *don't* return false in the
      # "allowed?" phase then we'll wind up sending out a cancel
      # notice every turn when there are no actions. So we add a
      # "silent" info option to the normal-every-turn cancellations,
      # but we *do* allow-then-cancel even in perfectly normal
      # circumstances.
      true
    end

    # If the agent can do so, take the action in question.
    def apply
      unless agent.state["busy"] > 0 || agent.state["queued_actions"].empty?
        # Pull the first entry off the action queue
        queue = @agent.state["queued_actions"]
        if queue && queue.size > 0
          if @action_queue_number != queue[0][2]
            @engine.admin_warning("Somehow the agent's action queue has gotten screwed up mid-offer!", "agent" => @name)
          else
            queue.shift # Remove the queue entry
          end
        end
        agent.run_action(@action_name, *@action_args, current_intention: self)
        agent.state["busy"] += (@action_struct["busy"] || 1)
      end
    end

    # Send out a notification to indicate this ActionIntention was
    # cancelled. If "silent" is set to true in the cancellation info,
    # no notification will be sent.
    #
    # @return [void]
    # @since 0.2.0
    def cancel_notification
      return if @cancelled_info && @cancelled_info["silent"]
      @engine.send_notification({
                                  reason: @cancelled_reason,
                                  by: @cancelled_by,
                                  id: @intention_id,
                                  intention_type: self.class.to_s,
                                  info: @cancelled_info,
                                  queue_number: @action_queue_number,
                                  action_name: @action_name,
                                  action_args: @action_args,
                                },
                                type: Demiurge::Notifications::IntentionCancelled,
                                zone: @item.zone_name,
                                location: @item.location_name,
                                actor: @item.name,
                                include_context: true)
      nil
    end

    # Send out a notification to indicate this ActionIntention was
    # applied.
    #
    # @return [void]
    # @since 0.2.0
    def apply_notification
      @engine.send_notification({
                                  id: @intention_id,
                                  intention_type: self.class.to_s,
                                  queue_number: @action_queue_number,
                                  action_name: @action_name,
                                  action_args: @action_args,
                                },
                                type: Demiurge::Notifications::IntentionApplied,
                                zone: @item.zone_name,
                                location: @item.location_name,
                                actor: @item.name,
                                include_context: true)
      nil
    end
  end

  # This agent will wander around. A simple way to make a decorative
  # mobile.  Do we want this longer term, or should it be merged into
  # the normal agent?
  class WanderingAgent < Agent
    # Constructor
    def initialize(name, engine, state)
      super
      state["wander_counter"] ||= 0
    end

    # If we're in a room but don't know where, pick a legal location.
    def finished_init
      super
      @wander_intention = AgentInternal::WanderIntention.new(engine, name)
      unless state["position"] && state["position"]["#"]
        # Move to legal position. If this is a TMX location or similar, it will assign a specific position.
        if self.location.respond_to?(:any_legal_position)
          state["position"] = self.location.any_legal_position
        end
      end
    end

    # Get intentions for the next upcoming tick
    def intentions_for_next_step
      super + [@wander_intention]
    end
  end

  # This is a simple Wandering agent for use with TmxLocations and similar grid-based maps.
  #
  # @api private
  class AgentInternal::WanderIntention < ActionItemInternal::ActionIntention
    # Constructor
    def initialize(engine, name, *args)
      @name = name
      super(engine, name, "", *args)
    end

    # Always allowed
    def allowed?
      true
    end

    # For now, WanderIntention is unblockable. That's not perfect, but
    # otherwise we have to figure out how to offer an action without
    # an action name.
    def offer
    end

    # Actually wander to an adjacent position, chosen randomly
    def apply
      agent = @engine.item_by_name(@name)
      agent.state["wander_counter"] += 1
      wander_every = agent.state["wander_every"] || 3
      return if agent.state["wander_counter"] < wander_every
      next_coords = agent.location.adjacent_positions(agent.position)
      if next_coords.empty?
        @engine.admin_warning("Oh no! Wandering agent #{@name.inspect} is stuck and can't get out!",
                             "zone" => agent.zone_name, "location" => agent.location_name, "agent" => @name)
        return
      end
      chosen = next_coords.sample
      pos = "#{agent.location_name}##{chosen.join(",")}"
      agent.move_to_position(pos, { "method" => "wander" })
      agent.state["wander_counter"] = 0
    end
  end
end
