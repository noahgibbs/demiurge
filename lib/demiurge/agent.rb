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
      @agent_maintenance = AgentMaintenanceIntention.new(engine, @name)
      state["busy"] ||= 0 # By default, start out idle.
    end

    # This method will move the agent and notify about that change. It
    # doesn't use an intention or an agent's action queue, and it
    # doesn't wait for a tick to happen. It just does it. The method
    # *does* handle exits and generally allows the location to
    # respond.  But it's assumed that the offer cycle, if it needs to
    # happen, has happened already.
    #
    # @param pos [String] A position string to move to
    # @return [void]
    # @since 0.0.1
    def move_to_position(pos)
      old_pos = self.position
      old_loc = self.location_name
      old_zone_name = self.zone_name
      expected_new_loc = pos.split("#")[0]

      if expected_new_loc == old_loc
        self.location.item_change_position(self, old_pos, pos)
      else
        # This also handles zone changes.
        self.location.item_change_location(self, old_pos, pos)
      end
      # We're not guaranteed to wind up where we expected, so get the
      # new location *after* item_change_location or
      # item_change_position.
      new_loc = self.location_name

      @engine.send_notification({ old_position: old_pos, old_location: old_loc, new_position: self.position, new_location: new_loc },
                                  type: "move_from", zone: old_zone_name, location: old_loc, actor: @name)
      @engine.send_notification({ old_position: old_pos, old_location: old_loc, new_position: self.position, new_location: new_loc },
                                  type: "move_to", zone: self.zone_name, location: self.location_name, actor: @name)
    end

    def intentions_for_next_step(options = {})
      agent_action = AgentActionIntention.new(@name, engine)
      super + [@agent_maintenance, agent_action]
    end

    def queue_action(action_name, *args)
      raise ::Demiurge::NoSuchActionError.new("Not an action: #{action_name.inspect}!", "action_name" => action_name) unless get_action(action_name)
      state["queued_actions"].push([action_name, args, state["queue_number"]])
      state["queue_number"] += 1
    end

    def clear_intention_queue
      state.delete "queued_actions"
    end
  end

  class AgentMaintenanceIntention < Intention
    def initialize(engine, name)
      @name = name
      super(engine)
    end

    # Normally, the agent's maintenance intention can't be blocked,
    # cancelled or modified.
    def offer(engine, intention_id, options)
    end

    def allowed?(engine, options)
      true
    end

    def apply(engine, options)
      agent = engine.item_by_name(@name)
      agent.state["busy"] -= 1 if agent.state["busy"] > 0
    end
  end

  class AgentActionIntention < ActionIntention
    attr_reader :agent
    attr_reader :action_name

    def initialize(name, engine)
      @name = name
      @engine = engine
      @agent = @engine.item_by_name(@name)
      raise NoSuchAgentError.new("No such agent as #{name.inspect} found in AgentActionIntention!", "agent" => @name) unless @agent
      super(engine, name, "")
    end

    def finished_init
    end

    # An action being pulled from the action queue is offered normally.
    def offer(engine, intention_id, options)
      # Don't offer the action if it's going to be a no-op.
      if @agent.state["busy"] > 0
        # See comment on "silent" in allowed?() below.
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
      super(engine, intention_id)
    end

    def allowed?(engine, options)
      # If the agent's busy state will clear this turn, this action could happen.
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

    def apply(engine, options)
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
  end

  # This agent will wander around. A simple way to make a decorative mobile.
  class WanderingAgent < Agent
    def initialize(name, engine, state)
      super
      @wander_intention = WanderIntention.new(engine, name)
      state["wander_counter"] ||= 0
    end

    def finished_init
      super
      unless state["position"] && state["position"]["#"]
        # Move to legal position. If this is a TMX location or similar, it will assign a specific position.
        if self.location.respond_to?(:any_legal_position)
          state["position"] = self.location.any_legal_position
        end
      end
    end

    def intentions_for_next_step(options = {})
      super + [@wander_intention]
    end
  end

  # This is a simple Wandering agent for use with TmxLocations and similar grid-based maps.
  class WanderIntention < ActionIntention
    def initialize(engine, name, *args)
      @name = name
      super(engine, name, "", *args)
    end

    def allowed?(engine, options)
      true
    end

    # For now, WanderIntention is unblockable. That's not perfect, but
    # otherwise we have to figure out how to offer an action without
    # an action name.
    def offer(engine, intention_id, options = {})
    end

    def apply(engine, options)
      agent = engine.item_by_name(@name)
      agent.state["wander_counter"] += 1
      wander_every = agent.state["wander_every"] || 3
      return if agent.state["wander_counter"] < wander_every
      next_coords = agent.zone.adjacent_positions(agent.position)
      if next_coords.empty?
        @engine.admin_warning("Oh no! Wandering agent #{@name.inspect} is stuck and can't get out!",
                             "zone" => agent.zone_name, "location" => agent.location_name, "agent" => @name)
        return
      end
      chosen = next_coords.sample
      pos = "#{agent.location_name}##{chosen.join(",")}"
      agent.move_to_position(pos)
      agent.state["wander_counter"] = 0
    end
  end
end
