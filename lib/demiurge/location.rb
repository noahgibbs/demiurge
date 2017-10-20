module Demiurge
  class Location < ActionItem
    # A Location isn't located "inside" somewhere else. It is located in/at itself.
    def location_name
      @name
    end

    # A Location isn't located "inside" somewhere else. It is located in/at itself.
    def location
      self
    end

    # A Location's zone name is set at construction and never changed.
    # I suppose we could take it out of the state, though that would
    # make it more painful to track and construct in the World Files.
    def zone_name
      @engine.state_for_property(@name, "zone")
    end

    def zone
      @engine.item_by_name(zone_name)
    end

    def initialize(name, engine)
      super(name, engine)
    end

    # Return a legal position of some kind within this Location.  By
    # default, that's just the Location's name.
    def any_legal_position
      @name
    end

    # Is this position valid in this location?
    def valid_position?(pos)
      pos == @name
    end
  end
end
