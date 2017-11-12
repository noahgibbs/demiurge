module Demiurge
  # A Zone is a top-level location. It may (or may not) contain
  # various sub-locations managed by the top-level zone, and it may be
  # quite large or quite small. Zones are the "magic" by which
  # Demiurge permits simulation of much larger areas than CPU allows,
  # up to and including "infinite" procedural areas where only a small
  # portion is continuously simulated.

  # A simplistic engine may contain only a small number of top-level
  # areas, each a zone in itself. A complex engine may have a small
  # number of areas, but each does extensive managing of its
  # sub-locations.

  class Zone < ActionItem
    def initialize(*args)
      super
      @state["location_names"] ||= []
      @state["agent_names"] ||= []
    end

    # A Zone isn't located "inside" somewhere else. It is located in/at itself.
    def location
      self
    end

    # A Zone isn't located "inside" somewhere else. It is located in/at itself.
    def location_name
      @name
    end

    # Similarly, a Zone has no position beyond itself.
    def position
      @name
    end

    # A Zone's zone is itself.
    def zone
      self
    end

    # A Zone's zone is itself.
    def zone_name
      @name
    end

    # Zones with locations contain instantiable agents and locations,
    # but not agents that actively *do* things. These agents won't
    # normally receive ticks or perform intentions.
    def add_agent(agent)
      old_zone = agent.zone
      old_zone.remove_agent(agent) if old_zone

      agent.state["zone"] = @name
      @state["agent_names"].push agent.name
    end

    def remove_agent(agent)
      @state["agent_names"] -= [ agent.name ]
      agent.state.delete "zone"
    end

    # By default, a Zone can accomodate any agent - especially because
    # this will be called when the agent is being added in "stasis",
    # normally for later instantiation.
    def can_accomodate_agent?(agent, position)
      true
    end

    # Note that "location" or "location_name" gets where the Zone
    # *is*. But location_names attempts to get a list of locations
    # *inside* the Zone. This may or may not do anything useful,
    # depending on the type of the Zone.
    def location_names
      @state["location_names"]
    end

    # By default, a zone just passes control to all its locations,
    # gathering up their intentions into a list.
    def intentions_for_next_step(options = {})
      intentions = @state["location_names"].flat_map do |loc_name|
        @engine.item_by_name(loc_name).intentions_for_next_step
      end
      intentions
    end

    # In some Zones this won't be meaningful. But for most "plain"
    # zones, this give possibilities of where is moveable for simple
    # AIs.
    def adjacent_positions(pos, options = {})
      []
    end
  end

  # In a RoomZone, locations are simple: you are in a Location, just
  # one at once, and exits allow movement between them. This is
  # similar to old MUDs, as well as games that present a store or
  # conversation as a separate screen that takes over your interface.
  class RoomZone < Zone
  end

  # In a TileZone, each Location is permitted to contain a coordinate
  # grid of sub-locations.  A given entity occupies one or more
  # sub-locations, but can't really be "in between" those
  # coordinates. Most frequently, objects take up a single
  # sub-location, or a small rectangle of them.
  class TileZone < Zone
  end
end
