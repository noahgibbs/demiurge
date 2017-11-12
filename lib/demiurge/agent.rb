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
  class Agent < ActionItem

    def initialize(*args)
      super
      state["queued_actions"] = []
    end

    def finished_init
      super
      @agent_maintenance = AgentMaintenanceIntention.new(@name)
      @agent_action = AgentActionIntention.new(@name, engine)
      state["busy"] ||= 0 # By default, start out idle.
    end

    # This will move the agent, instantly, without going through the
    # usual cycle of movement. It just drops this agent in a new place
    # without going through the usual action cycle. It *does* notify
    # about the change, though.
    def move_to_position(pos)
      old_pos = self.position
      old_loc = self.location_name
      old_loc_item = self.location
      old_zone = self.zone_name
      new_loc, new_coords = pos.split("#", 2)
      new_loc_item = @engine.item_by_name(new_loc)
      new_zone = new_loc_item.zone_name

      self.state["position"] = pos

      if new_zone != old_zone
        old_zone_item = @engine.item_by_name(old_zone)
        old_zone_item.remove_agent(self)
        self.state["zone"] = new_zone
      end

      @engine.send_notification({ old_position: old_pos, old_location: old_loc, new_position: pos, new_location: new_loc },
                                  notification_type: "move", zone: self.zone_name, location: self.location_name, item_acting: @name)
    end

    def intentions_for_next_step(options = {})
      super + [@agent_maintenance, @agent_action]
    end

    def queue_action(action_name, *args)
      raise("Not an action: #{action_name.inspect}!") unless get_action(action_name)
      state["queued_actions"].push([action_name, args])
    end

    def clear_intention_queue
      state.delete "queued_actions"
    end
  end

  class AgentMaintenanceIntention < Intention
    def initialize(name)
      @name = name
    end

    # Normally, the agent's maintenance intention can't be blocked or
    # modified.
    def offer(engine, options)
    end

    def allowed?(engine, options)
      true
    end

    def apply(engine, options)
      agent = engine.item_by_name(@name)
      agent.state["busy"] -= 1 if agent.state["busy"] > 0
    end
  end

  class AgentActionIntention < Intention
    attr_reader :agent
    attr_reader :action_name

    def initialize(name, engine)
      @name = name
      @engine = engine
      @agent = @engine.item_by_name(@name)
      raise "No such agent as #{name.inspect} found!" unless @agent
    end

    def finished_init
    end

    # An action being pulled from the action queue is offered normally.
    def offer(engine, options)
      unless @agent.state["busy"] > 0 || @agent.state["queued_actions"].empty?
        action = @agent.state["queued_actions"][0]
        @action_name = action[0]
        @action_args = action[1]
        @action_struct = @agent.get_action(@action_name)
      end
      # TODO: offer the action to the agent's location and potentially other appropriate places.
    end

    def allowed?(engine, options)
      # If the agent's busy state will clear this turn, this action could happen.
      @agent.state["busy"] <= 1
    end

    def apply(engine, options)
      unless agent.state["busy"] > 0 || agent.state["queued_actions"].empty?
        # Pull the first entry off the action queue
        queue = @agent.state["queued_actions"]
        if queue && queue.size > 0 && queue[0] == @action_name && queue[1] == @action_args
          queue.shift # Remove the queue entry
        end
        agent.run_action(@action_name, *@args)
        agent.state["busy"] += (@action_struct["busy"] || 1)
      end
    end
  end

  # This agent will wander around. A simple way to make a decorative mobile.
  class WanderingAgent < Agent
    def initialize(name, engine, state)
      super
      @wander_intention = WanderIntention.new(name)
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
  class WanderIntention < Intention
    def initialize(name)
      @name = name
    end

    def allowed?(engine, options)
      true
    end

    # Later, wander should be cancellable and it should be possible
    # for a room to move the agent through an exit. For now, nope.
    def offer(engine, options)
    end

    def apply(engine, options)
      agent = engine.item_by_name(@name)
      agent.state["wander_counter"] += 1
      wander_every = agent.state["wander_every"] || 3
      return if agent.state["wander_counter"] < wander_every
      next_coords = agent.zone.adjacent_positions(agent.position)
      if next_coords.empty?
        engine.send_notification({ description: "Oh no! Wandering agent #{@name.inspect} is stuck and can't get out!" }, notification_type: "admin warning", zone: agent.zone_name, location: agent.location_name, item_acting: @name)
        return
      end
      chosen = next_coords.sample
      pos = "#{agent.location_name}##{chosen.join(",")}"
      agent.move_to_position(pos)
      agent.state["wander_counter"] = 0
    end
  end
end
