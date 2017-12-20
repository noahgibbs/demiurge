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
end
