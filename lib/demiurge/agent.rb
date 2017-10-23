module Demiurge

  # Agents correspond roughly to "mobiles" in many games. An agent
  # isn't particularly different from other Demiurge objects, but it's
  # useful to have some helper classes for things like pathfinding.
  class Agent < ActionItem
    def move_to_position(pos)
      old_pos = self.position
      old_loc = self.location_name
      old_loc_item = self.location
      old_zone = self.zone_name
      new_loc, new_coords = pos.split("#", 2)
      new_loc_item = @engine.item_by_name(new_loc)
      new_zone = new_loc_item.zone_name

      # This will move the agent... And is going to be the wrong way
      # to do this soon. There's a whole
      # Intention/Offer/Resolve/Notify cycle that this skips, which is
      # fine if and only if that's handled some other way and this is
      # just the "resolve". But, like, how do we handle exits
      # automatically sending you to a new tileset and special
      # encounters/spaces and stuff?
      self.state["position"] = pos

      if new_zone != old_zone
        raise "Cross-zone travel is unimplemented!"
      else
        @engine.send_notification({ old_position: self.position, old_location: old_loc, new_position: pos, new_location: new_loc },
                                  notification_type: "move", zone: self.zone_name, location: self.location_name, item_acting: @name)
      end
    end

  end

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
      next_coords = agent.zone.adjacent_positions(agent.position)
      if next_coords.empty?
        engine.send_notification({ description: "Oh no! Wandering agent #{@name.inspect} is stuck and can't get out!" }, notification_type: "admin warning", zone: agent.zone_name, location: agent.location_name, item_acting: @name)
        return
      end
      chosen = next_coords.sample
      pos = "#{agent.location_name}##{chosen.join(",")}"
      agent.move_to_position(pos)
    end
  end
end
