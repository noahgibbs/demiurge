module Demiurge
  class Location < ActionItem
    def initialize(name, engine, state)
      super
      state["contents"] ||= []
      state["exits"] ||= []
    end

    def finished_init
      # Can't move all items inside until they all exist, which isn't guaranteed until init is finished.
      state["contents"].each do |item|
        move_item_inside(@engine.item_by_name(item))
      end

      # And make sure we're in our zone.
      zone.state["location_names"] |= [@name]
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
    # I suppose we could take the zone out of the location's state,
    # though that would make it more painful to track and construct in
    # the World Files.
    def zone_name
      @state["zone"]
    end

    def zone
      @engine.item_by_name(@state["zone"])
    end

    def ensure_does_not_contain(item_name)
      @state["contents"] -= [item_name]
    end

    def move_item_inside(item)
      old_pos = item.position
      if old_pos && old_pos != ""
        old_loc_name = old_pos.split("#")[0]
        old_loc = @engine.item_by_name(old_loc_name)
        old_loc.ensure_does_not_contain(item.name)
      end

      @state["contents"] += [ item.name ]
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

    # Include everything under the location: anything have an action to perform?
    def intentions_for_next_step(options = {})
      intentions = super
      @state["contents"].each do |item_name|
        item = @engine.item_by_name(item_name)
        intentions += item.intentions_for_next_step(options)
      end
      intentions
    end
  end
end
