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
    def zone_name
      @engine.state_for_property(@name, "zone")
    end

    def zone
      @engine.item_by_name(zone_name)
    end

    def initialize(name, engine)
      super(name, engine)
    end
  end
end
