module Demiurge
  class Location < ActionItem
    def initialize(name, engine)
      super
    end

    def finished_init
      state["contents"] ||= []
      state["contents"].each do |item|
        move_item_inside(@engine.item_by_name(item))
      end
    end

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

    def ensure_does_not_contain(item_name)
      state["contents"] -= [item_name]
    end

    def move_item_inside(item)
      old_pos = item.position
      if old_pos && old_pos != ""
        old_loc_name = old_pos.split("#")[0]
        old_loc = @engine.item_by_name(old_loc_name)
        old_loc.ensure_does_not_contain(item.name)
      end

      state["contents"] += [ item.name ]
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

    # Include everything under the location: anything have an action to perform?
    def intentions_for_next_step(options = {})
      intentions = super
      state["contents"].each do |item_name|
        item = @engine.item_by_name(item_name)
        intentions += item.intentions_for_next_step(options)
      end
      intentions
    end
  end
end
