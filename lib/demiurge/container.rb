# A Container may contain other items. Common examples include Zones and Locations.

module Demiurge
  # Container is the parent class of Locations, Zones and other items that can contain items.
  class Container < ActionItem
    # Constructor - set up contents
    #
    # @param name [String] The Engine-unique item name
    # @param engine [Demiurge::Engine] The Engine this item is part of
    # @param state [Hash] State data to initialize from
    # @return [void]
    # @since 0.0.1
    def initialize(name, engine, state)
      super
      state["contents"] ||= []
    end

    # Gets the array of item names of all items contained in this
    # container.
    #
    # @return [Array<String>] The array of item names
    # @since 0.0.1
    def contents_names
      state["contents"]
    end

    # The finished_init hook is called after all items are loaded. For
    # containers, this makes sure all items set as contents of this
    # container also have it correctly set as their position.
    #
    # @return [void]
    # @since 0.0.1
    def finished_init
      # Can't move all items inside until they all exist, which isn't guaranteed until init is finished.
      state["contents"].each do |item|
        move_item_inside(@engine.item_by_name(item))
      end
      nil
    end

    # This makes sure the given item name is listed in the container's
    # contents. It does *not* make sure that the item currently
    # exists, or that its position is set to this container.
    #
    # @see #move_item_inside
    # @see #ensure_does_not_contain
    # @param item_name [String] The item name to ensure is listed in the container
    # @return [void]
    # @since 0.0.1
    def ensure_contains(item_name)
      raise("Pass only item names to ensure_contains!") unless item_name.is_a?(String)
      @state["contents"] |= [item_name]
      nil
    end

    # This makes sure the given item name is *not* listed in the
    # container's contents. It does not make sure the item exists, nor
    # do anything with the item's position.
    #
    # @see #ensure_contains
    # @see #move_item_inside
    # @param item_name [String] The item name
    # @return [void]
    # @since 0.0.1
    def ensure_does_not_contain(item_name)
      raise("Pass only item names to ensure_does_not_contain!") unless item_name.is_a?(String)
      @state["contents"] -= [item_name]
      nil
    end

    # This makes sure the given StateItem is contained in this
    # container. It sets the item's position to be in this container,
    # and if there is an old location it attempts to properly remove
    # the item from it.
    #
    # @see Demiurge::Agent#move_to_position
    # @param item [Demiurge::StateItem] The item to be moved into this container
    # @return [void]
    # @since 0.0.1
    def move_item_inside(item)
      old_pos = item.position
      if old_pos
        old_loc_name = old_pos.split("#")[0]
        old_loc = @engine.item_by_name(old_loc_name)
        old_loc.ensure_does_not_contain(item.name)
      end

      @state["contents"] |= [ item.name ]
      nil
    end

    # This is a callback to indicate that an item has changed
    # position, but remains inside this location. Other than changing
    # the item's position state variable, this may not require any
    # changes. A different callback is called when the item changes
    # from one location to another.
    #
    # @see #item_change_location
    # @param item [Demiurge::StateItem] The item changing position
    # @param old_pos [String] The pre-movement position, which is current when this is called
    # @param new_pos [String] The post-movement position, which should be current when this method completes
    # @return [void]
    # @since 0.0.1
    def item_change_position(item, old_pos, new_pos)
      item.state["position"] = new_pos
      nil
    end

    # This is a callback to indicate that an item has changed from one
    # location to another. This will normally require removing the
    # item from its first location and adding it to a new location.  A
    # different callback is called when the item changes position
    # within a single location.
    #
    # @see #item_change_position
    # @param item [Demiurge::StateItem] The item changing position
    # @param old_pos [String] The pre-movement position, which is current when this is called
    # @param new_pos [String] The post-movement position, which should be current when this method completes
    # @return [void]
    # @since 0.0.1
    def item_change_location(item, old_pos, new_pos)
      old_loc = old_pos.split("#")[0]
      old_loc_item = @engine.item_by_name(old_loc)
      old_loc_item.ensure_does_not_contain(item.name)
      new_loc = new_pos.split("#")[0]
      new_loc_item = @engine.item_by_name(new_loc)
      new_loc_item.ensure_contains(item.name)
      item.state["position"] = new_pos

      old_zone = old_loc_item.zone_name
      new_zone = new_loc_item.zone_name
      if new_zone != old_zone
        item.state["zone"] = new_zone
      end
      nil
    end

    # When an item has an {Demiurge::Intention}, that Intention is
    # offered in order to be potentially modified or canceled by
    # environmental effects. For instance, a room might have a muddy
    # floor that slows walking or prevents running, or an icy floor
    # that causes sliding around. That offer is normally coordinated
    # through the item's location. The location will receive this
    # callback ({#receive_offer}) and make appropriate modifications
    # to the Intention. Any other items or agents that want to modify
    # the Intention will have to coordinate with the appropriate item
    # location.
    #
    # @see file:CONCEPTS.md
    # @param action_name [String] The name of the action for this Intention.
    # @param intention [Demiurge::Intention] The Intention being offered
    # @param intention_id [Integer] The assigned intention ID for this Intention
    # @return [void]
    # @since 0.0.1
    def receive_offer(action_name, intention, intention_id)
      # Run handlers, if any
      on_actions = @state["on_action_handlers"]
      if on_actions && (on_actions[action_name] || on_actions["all"])
        run_action(on_actions["all"], intention, current_intention: intention) if on_actions["all"]
        run_action(on_actions[action_name], intention, current_intention: intention) if on_actions[action_name]
      end
      nil
    end

    # This method determines if a given agent can exist at the
    # specified position inside this container.  By default, a
    # container can accomodate anyone or anything. Subclass to change
    # this behavior. This should take into account the size, shape and
    # current condition of the agent, and might take into account
    # whether the agent has certain movement abilities.
    #
    # @param agent [Demiurge::Agent] The agent being checked
    # @param position [String] The position being checked within this container
    # @return [Boolean] Whether the agent can exist at that position
    # @since 0.0.1
    def can_accomodate_agent?(agent, position)
      true
    end

    # This determines the intentions for the next tick for this
    # container and for all items inside it.
    #
    # @return [Array<Intention>] The array of intentions for next tick
    # @since 0.0.1
    def intentions_for_next_step
      intentions = super
      @state["contents"].each do |item_name|
        item = @engine.item_by_name(item_name)
        intentions += item.intentions_for_next_step
      end
      intentions
    end

  end
end
