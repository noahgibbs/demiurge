require_relative 'test_helper'

require "demiurge/dsl"

class ZoneSubtype < Demiurge::Zone; end
Demiurge::DSL::TopLevelBuilder.register_type "ZoneSubtype", ZoneSubtype

class StateRestoreTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "moss caves" do
      location "first moss cave" do
        description "This cave is dim, with smooth sides. You can see delicious moss growing inside, out of the hot sunlight."
        state.moss = 0

        every_X_ticks("grow", 3) do
          state.moss += 1
          notification description: "The moss slowly grows longer and more lush here."
        end
      end

      location "second moss cave" do
        description "A recently-opened cave here has jagged walls, and delicious-looking stubbly moss in between the cracks."
        state.moss = 0
        state.softer_moss = 0
        state.no_flash = true
        state.messages = []

        every_X_ticks("grow", 3) do
          state.moss += 1
          state.softer_moss += 7
          notification description: "The moss in the cracks seems to get thicker and softer moment by moment."
        end

        agent "wanderer", "type" => "WanderingAgent" do
        end

        on_intention("flash of light", "see the flash") do
          state.saw_maybe_flash = true
          if state.no_flash
            cancel_intention "This room is in no way groovy enough."
          end
        end

        on_notification("sight", "check the sights") do |n|
          state.messages.push(n["message"])
          if n["mirrored"]
            state.totally_funky = true
          end
        end

        agent "disco bandit" do
          state.mirrored = false

          define_action("flash of light") do
            if state.mirrored
              notification "type": "sight", "message": "A bright double burst of light fills the room!", "mirrored": true
            else
              notification "type": "sight", "message": "A bright burst of light fills the room!"
            end
          end
        end
      end
    end
  DSL

  def test_dsl_actions_after_state_restore
    engine = Demiurge::DSL.engine_from_dsl_text(["State Restore DSL", DSL_TEXT])
    first_cave_item = engine.item_by_name("first moss cave")
    refute_nil first_cave_item
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item
    agent = engine.item_by_name("wanderer")
    refute_nil agent
    assert_equal "second moss cave", agent.location_name

    notification_queue = []
    engine.subscribe_to_notifications(type: "load_state_start") do |notification|
      notification_queue.push notification["type"]
    end
    engine.subscribe_to_notifications(type: "load_state_end") do |notification|
      notification_queue.push notification["type"]
    end

    # Dump and restore before anything interesting happens...
    ss = engine.structured_state
    engine.load_state_from_dump(ss)
    engine.flush_notifications
    assert_equal [ "load_state_start", "load_state_end" ], notification_queue

    # Re-query items, which may have been recreated
    first_cave_item = engine.item_by_name("first moss cave")
    refute_nil first_cave_item
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item
    agent = engine.item_by_name("wanderer")
    refute_nil agent
    assert_equal "second moss cave", agent.location_name

    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]

    engine.advance_one_tick
    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]

    engine.advance_one_tick
    engine.advance_one_tick

    assert_equal 1, first_cave_item.state["moss"]
    assert_nil first_cave_item.state["softer_moss"]
    assert_equal 1, second_cave_item.state["moss"]
    assert_equal 7, second_cave_item.state["softer_moss"]
  end

  def test_dsl_actions_with_middle_state_restore
    engine = Demiurge::DSL.engine_from_dsl_text(["State Restore DSL", DSL_TEXT])
    first_cave_item = engine.item_by_name("first moss cave")
    refute_nil first_cave_item
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item
    agent = engine.item_by_name("wanderer")
    refute_nil agent
    assert_equal "second moss cave", agent.location_name

    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]

    # Dump and restore in the middle of all this...
    ss = engine.structured_state
    engine.load_state_from_dump(ss)

    engine.advance_one_tick
    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]

    engine.advance_one_tick
    engine.advance_one_tick
    assert_equal 1, first_cave_item.state["moss"]
    assert_nil first_cave_item.state["softer_moss"]
    assert_equal 1, second_cave_item.state["moss"]
    assert_equal 7, second_cave_item.state["softer_moss"]
  end

  def test_intentions_and_notifications_across_state_restore
    engine = Demiurge::DSL.engine_from_dsl_text(["State Restore DSL", DSL_TEXT])
    disco_cave = engine.item_by_name("second moss cave")
    bandit = engine.item_by_name("disco bandit")

    # Dump and restore to check if on_intention and on_notification keep working
    ss = engine.structured_state
    engine.load_state_from_dump(ss)

    notifications = []
    engine.subscribe_to_notifications("type": ["intention_cancelled", "sight"]) do |n|
      notifications.push(n)
    end

    # Dump and restore to check if subscribe_to_notifications keeps working
    ss = engine.structured_state
    engine.load_state_from_dump(ss)

    assert !disco_cave.state["saw_maybe_flash"], "The cave shouldn't have seen any flash yet!"
    assert notifications.size == 0, "There shouldn't be any notifications since we just started!"
    bandit.queue_action("flash of light")  # Right now, the cave is set "no_flash" and will cancel it.
    # Dump and restore to check if the queued action still happens...
    ss = engine.structured_state
    engine.load_state_from_dump(ss)
    # Done w/ restore, now go forward a tick
    engine.advance_one_tick
    assert_equal "intention_cancelled", notifications[0]["type"]
    assert disco_cave.state["saw_maybe_flash"] == true, "The cave should have seen a flash and cancelled the action!"
    notifications.pop  # Clear the queue

    # Dump and restore, just in case
    ss = engine.structured_state
    engine.load_state_from_dump(ss)

    disco_cave.state["no_flash"] = false  # Now the flash can happen, the cave won't cancel it
    bandit.queue_action("flash of light")
    engine.advance_one_tick
    assert_equal 1, notifications.size
    assert_equal "sight", notifications[0]["type"]
    notifications.pop

    # Dump and restore to check if everything still works
    ss = engine.structured_state
    engine.load_state_from_dump(ss)

    bandit.state["mirrored"] = true
    bandit.queue_action("flash of light")
    # Dump and restore to check if the queued action still happens...
    ss = engine.structured_state
    engine.load_state_from_dump(ss)
    # Done w/ restore, now go forward a tick
    engine.advance_one_tick
    assert_equal 1, notifications.size
    assert_equal "sight", notifications[0]["type"]
    assert disco_cave.state["totally_funky"] == true, "The cave didn't get totally funky! Something is wrong!"
    notifications.pop
  end
end
