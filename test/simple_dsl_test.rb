require_relative 'test_helper'

require "demiurge/dsl"

class ZoneSubtype < Demiurge::Zone; end
Demiurge::DSL::TopLevelBuilder.register_type "ZoneSubtype", ZoneSubtype

class SimpleDslTest < Minitest::Test
  DSL_TEXT = <<-GOBLIN_DSL
    inert "config_settings"
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

        every_X_ticks("grow", 3) do
          state.moss += 1
          notification description: "The moss in the cracks seems to get thicker and softer moment by moment."
        end

        agent "wanderer", "type" => "WanderingAgent" do
          # Don't declare a location - this should get one automatically.
        end
      end
    end
  GOBLIN_DSL

  def test_trivial_dsl_actions
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", DSL_TEXT])
    first_cave_item = engine.item_by_name("first moss cave")
    refute_nil first_cave_item
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item
    agent = engine.item_by_name("wanderer")
    refute_nil agent
    assert_equal "second moss cave", agent.location_name

    settings_item = engine.item_by_name("config_settings")
    refute_nil settings_item

    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]
    # We don't apply these intentions - they get recalculated when the engine advances.
    intentions = engine.next_step_intentions
    assert_equal 5, intentions.size  # Two from the moss caves, three from the agent

    engine.advance_one_tick
    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]

    # We don't apply these intentions - they get recalculated when the engine advances.
    intentions = engine.next_step_intentions
    engine.advance_one_tick
    intentions = engine.next_step_intentions
    engine.advance_one_tick
    assert_equal 1, first_cave_item.state["moss"]
    assert_equal 1, second_cave_item.state["moss"]
    engine.flush_notifications # For completeness and to notice exceptions, basically
  end

  def test_dsl_type_specs
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", <<-DSL_TEXT])
zone "first zone", "type" => "ZoneSubtype" do
end
    DSL_TEXT
    zone = engine.item_by_name("first zone")
    assert_equal "ZoneSubtype", zone.class.to_s
  end

  def test_item_unregister
    engine = Demiurge.engine_from_dsl_text(["Simple DSL Test", DSL_TEXT])
    agent = engine.item_by_name("wanderer")
    refute_nil agent

    engine.unregister_state_item(agent)
    agent = engine.item_by_name("wanderer")
    assert_nil agent

    engine.advance_one_tick  # Check for exception
  end
end
