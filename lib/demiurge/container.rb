# A Container may contain other items. Common examples include Zones and Locations.

module Demiurge
  class Container < ActionItem
    def initialize(name, engine, state)
      super
      state["contents"] ||= []
    end

    def contents_names
      state["contents"]
    end

    def finished_init
      # Can't move all items inside until they all exist, which isn't guaranteed until init is finished.
      state["contents"].each do |item|
        move_item_inside(@engine.item_by_name(item))
      end
    end

    def ensure_contains(item_name)
      raise("Pass only item names to ensure_contains!") unless item_name.is_a?(String)
      @state["contents"] |= [item_name]
    end

    def ensure_does_not_contain(item_name)
      raise("Pass only item names to ensure_does_not_contain!") unless item_name.is_a?(String)
      @state["contents"] -= [item_name]
    end

    def move_item_inside(item)
      old_pos = item.position
      if old_pos
        old_loc_name = old_pos.split("#")[0]
        old_loc = @engine.item_by_name(old_loc_name)
        old_loc.ensure_does_not_contain(item.name)
      end

      @state["contents"] |= [ item.name ]
    end

    # This doesn't necessarily require a reaction, and will normally
    # only happen when the location isn't changing.
    def item_change_position(item, old_pos, new_pos)
      item.state["position"] = new_pos
    end

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
    end

    def receive_offer(action_name, intention, intention_id)
      # Run handlers, if any
      on_actions = @state["on_action_handlers"]
      if on_actions && (on_actions[action_name] || on_actions["all"])
        run_action(on_actions["all"], intention) if on_actions["all"]
        run_action(on_actions[action_name], intention) if on_actions[action_name]
      end
    end

    # By default, a container can accomodate anyone or anything. Subclass to change this behavior.
    def can_accomodate_agent?(agent, position)
      true
    end

    # Include everything under the container: anything have an action to perform?
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
