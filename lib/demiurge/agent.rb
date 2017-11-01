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
      @intention_queue = []
      @agent_maintenance = AgentMaintenanceIntention.new(@name)
      state["busy"] ||= 0 # By default, start out idle.
    end

    # This will move the agent... And is going to be the wrong way to
    # do this soon. There's a whole Intention/Offer/Resolve/Notify
    # cycle that this skips, which is fine if and only if that's
    # handled some other way and this is just the "resolve". But,
    # like, how do we handle exits and special encounters/spaces and
    # stuff?
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
        raise "Cross-zone travel is unimplemented!"
      else
        @engine.send_notification({ old_position: old_pos, old_location: old_loc, new_position: pos, new_location: new_loc },
                                  notification_type: "move", zone: self.zone_name, location: self.location_name, item_acting: @name)
      end
    end

    def intentions_for_next_step(options = {})
      current = []
      # TODO: just add an action to check if not busy? Then we could queue an action with an "every" and execute it on the same tick.
      unless state["busy"] > 0 || @intention_queue.empty?
        # Pull the first entry off the Intention queue
        current = [@intention_queue.shift]
      end
      super + current + [@agent_maintenance]
    end

    def queue_intention(intention)
      raise("Not an intention: #{intention.inspect}!") unless intention.is_a?(Intention)
      @intention_queue.push(intention)
    end

    def clear_intention_queue
      @intention_queue = []
    end
  end

  class AgentMaintenanceIntention < Intention
    def initialize(name)
      @name = name
    end

    def allowed?(engine, options)
      true
    end

    def apply(engine, options)
      agent = engine.item_by_name(@name)
      agent.state["busy"] -= 1 if agent.state["busy"] > 0
    end
  end

  # This agent will wander around. A simple way to make a decorative mobile.
  class WanderingAgent < Agent
    def initialize(name, engine)
      super
      @wander_intention = WanderIntention.new(name)
    end

    def finished_init
      super
      unless state["position"]["#"]
        # Move to legal position. If this is a TMX location or similar, it will assign a specific position.
        if self.location.respond_to?(:any_legal_position)
          state["position"] = self.location.any_legal_position
        end
      end
      state["wander_counter"] ||= 0
    end

    def intentions_for_next_step(options = {})
      super + [@wander_intention]
    end
  end

  class WanderIntention < Intention
    def initialize(name)
      @name = name
    end

    def allowed?(engine, options)
      true
    end

    def apply(engine, options)
      agent = engine.item_by_name(@name)
      state = engine.state_for_item(@name)
      state["wander_counter"] += 1
      wander_every = state["wander_every"] || 3
      return if state["wander_counter"] < wander_every
      next_coords = agent.zone.adjacent_positions(agent.position)
      if next_coords.empty?
        engine.send_notification({ description: "Oh no! Wandering agent #{@name.inspect} is stuck and can't get out!" }, notification_type: "admin warning", zone: agent.zone_name, location: agent.location_name, item_acting: @name)
        return
      end
      chosen = next_coords.sample
      pos = "#{agent.location_name}##{chosen.join(",")}"
      agent.move_to_position(pos)
      state["wander_counter"] = 0
    end
  end

end
