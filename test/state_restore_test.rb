require_relative 'test_helper'

require "demiurge/dsl"

class ZoneSubtype < Demiurge::Zone; end
Demiurge::TopLevelBuilder.register_type "ZoneSubtype", ZoneSubtype

class StateRestoreTest < Minitest::Test
  DSL_TEXT = <<-GOBLIN_DSL
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

        every_X_ticks("grow", 3) do
          state.moss += 1
          state.softer_moss += 7
          notification description: "The moss in the cracks seems to get thicker and softer moment by moment."
        end

        agent "wanderer", "type" => "WanderingAgent" do
          # Don't declare a location - this should get one automatically.
        end
      end
    end
  GOBLIN_DSL

  def test_dsl_actions_after_state_restore
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", DSL_TEXT])
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
    # We won't apply these intentions, they get calculated again when advancing a tick.
    intentions = engine.next_step_intentions
    assert_equal 5, intentions.size  # Two from the moss caves, three from the agent

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
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", DSL_TEXT])
    first_cave_item = engine.item_by_name("first moss cave")
    refute_nil first_cave_item
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item
    agent = engine.item_by_name("wanderer")
    refute_nil agent
    assert_equal "second moss cave", agent.location_name

    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]
    intentions = engine.next_step_intentions
    assert_equal 5, intentions.size  # Two from the moss caves, three from the agent

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

  def test_dsl_type_specs
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", <<-DSL_TEXT])
zone "first zone", "type" => "ZoneSubtype" do
end
    DSL_TEXT
    zone = engine.item_by_name("first zone")
    assert_equal "ZoneSubtype", zone.class.to_s
  end
end
