module Demiurge
  # A Location is generally found inside a Zone.  It may contain items
  # and agents.
  class Location < Container
    # Constructor - set up exits
    #
    # @param name [String] The Engine-unique item name
    # @param engine [Demiurge::Engine] The Engine this item is part of
    # @param state [Hash] State data to initialize from
    # @return [void]
    # @since 0.0.1
    def initialize(name, engine, state)
      super
      state["exits"] ||= []
    end

    def finished_init
      super
      # Make sure we're in our zone.
      zone.ensure_contains(@name)
    end

    # A Location isn't located "inside" somewhere else. It is located in/at itself.
    def location_name
      @name
    end

    # A Location isn't located "inside" somewhere else. It is located in/at itself.
    def location
      self
    end

    def zone_name
      @state["zone"]
    end

    def zone
      @engine.item_by_name(@state["zone"])
    end

    # By default, the location can accomodate any agent number, size
    # or shape, as long as it's in this location itself.  Subclasses
    # of location may have different abilities to accomodate different
    # sizes or shapes of agent, and at different positions.
    def can_accomodate_agent?(agent, position)
      position == @name
    end

    # Return a legal position of some kind within this Location.  By
    # default there is only one position, which is just the Location's
    # name. More complicated locations (e.g. tilemaps or procedural
    # areas) may have more interesting positions inside them.
    def any_legal_position
      @name
    end

    # Is this position valid in this location?
    def valid_position?(pos)
      pos == @name
    end

    def add_exit(from:any_legal_position, to:, to_location: nil, properties:{})
      to_loc, to_coords = to.split("#",2)
      if to_location == nil
        to_location = @engine.item_by_name(to_loc)
      end
      raise("'From' position #{from.inspect} is invalid when adding exit to #{@name.inspect}!") unless valid_position?(from)
      raise("'To' position #{to.inspect} is invalid when adding exit to #{@name.inspect}!") unless to_location.valid_position?(to)
      exit_obj = { "from" => from, "to" => to, "properties" => properties }
      @state["exits"] ||= []
      @state["exits"].push(exit_obj)
      exit_obj
    end

    # This isn't guaranteed to be in a particular format for all
    # Locations everywhere. Sometimes exits in this form don't even
    # make sense. So: this is best-effort when queried from a random
    # Location, and a known format only if you know the specific
    # subclass of Location you're dealing with.
    def exits
      @state["exits"]
    end

  end

  class TiledLocation < Location
    # Parse a tiled position string and return the X and Y tile coordinates
    def self.position_to_coords(pos)
      loc, x, y = position_to_loc_coords(pos)
      return x, y
    end

    # Parse a tiled position string and return the location name and the X and Y tile coordinates
    def self.position_to_loc_coords(pos)
      loc, coords = pos.split("#",2)
      if coords
        x, y = coords.split(",")
        return loc, x.to_i, y.to_i
      else
        return loc, nil, nil
      end
    end

    # When an item changes position in a TiledLocation, check if the
    # new position leads out an exit. If so, send them where the exit
    # leads instead.
    def item_change_position(item, old_pos, new_pos)
      exit = @state["exits"].detect { |e| e["from"] == new_pos }
      return super unless exit  # No exit? Do what you were going to.

      # Going to hit an exit? Cancel this motion and enqueue an
      # intention to do so? Or just send them through? If the former,
      # it's very hard to unblockably pass through an exit, even if
      # that's what's wanted. If the latter, it's very hard to make
      # going through an exit blockable.

      # Eh, just send them through for now. We'll figure out how to
      # make detecting and blocking exit intentions easy later.

      item_change_location(item, old_pos, exit["to"])
    end

    # This just determines if the position is valid at all.  It does
    # *not* check walkable/swimmable or even if it's big enough for a
    # humanoid to stand in.
    def valid_position?(pos)
      return false unless pos[0...@name.size] == @name
      return false unless pos[@name.size] == "#"
      x, y = pos[(@name.size + 1)..-1].split(",", 2).map(&:to_i)
      valid_coordinate?(x, y)
    end

    # Determine whether this position can accomodate the given agent's shape and size.
    def can_accomodate_agent?(agent, position)
      loc, x, y = TiledLocation.position_to_loc_coords(position)
      raise "Location #{@name.inspect} asked about different location #{loc.inspect} in can_accomodate_agent!" if loc != @name
      shape = agent.state["shape"] || "humanoid"
      can_accomodate_shape?(x, y, shape)
    end

    def valid_coordinate?(x,y)
      true
    end

    def can_accomodate_dimensions?(left_x, upper_y, width, height)
      true
    end

    # Determine whether this coordinate location can accomodate an
    # item of the given shape.
    #
    # For now, don't distinguish between walkable/swimmable or
    # whatever, just say a collision value of 0 means valid,
    # everything else is invalid.
    #
    # TODO: figure out some configurable way to specify what tile
    # value means invalid for TMX maps with more complex collision
    # logic.
    def can_accomodate_shape?(left_x, upper_y, shape)
      case shape
      when "humanoid"
        return can_accomodate_dimensions?(left_x, upper_y, 2, 1)
      when "tiny"
        return can_accomodate_dimensions?(left_x, upper_y, 1, 1)
      else
        raise "Unknown shape #{shape.inspect} passed to can_accomodate_shape!"
      end
    end

    def any_legal_position
      "#{@name}#0,0"
    end
  end
end
