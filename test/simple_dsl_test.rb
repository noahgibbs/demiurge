require_relative 'test_helper'

require "demiurge/dsl"

class ZoneSubtype < Demiurge::Zone; end
Demiurge::TopLevelBuilder.register_type "ZoneSubtype", ZoneSubtype

class SimpleDslTest < Minitest::Test
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

        every_X_ticks("grow", 3) do
          state.moss += 1
          notification description: "The moss in the cracks seems to get thicker and softer moment by moment."
        end
      end
    end

    #agent "player" do
    #  type "PlayerAgent"
    #  state.start_zone = "moss caves"
    #end
  GOBLIN_DSL

  def test_trivial_dsl_actions
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", DSL_TEXT])
    engine.finished_init
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item

    assert_equal 0, engine.state_for_property("first moss cave", "moss")
    assert_equal 0, engine.state_for_property("second moss cave", "moss")
    intentions = engine.next_step_intentions
    assert_equal 2, intentions.size

    engine.apply_intentions(intentions)
    assert_equal 0, engine.state_for_property("first moss cave", "moss")
    assert_equal 0, engine.state_for_property("second moss cave", "moss")

    intentions = engine.next_step_intentions
    engine.apply_intentions(intentions)
    intentions = engine.next_step_intentions
    engine.apply_intentions(intentions)
    assert_equal 1, engine.state_for_property("first moss cave", "moss")
    assert_equal 1, engine.state_for_property("second moss cave", "moss")
  end

  def test_dsl_type_specs
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", <<-DSL_TEXT])
zone "first zone" do
  type "ZoneSubtype"
end
    DSL_TEXT
    engine.finished_init
    zone = engine.item_by_name("first zone")
    assert_equal "ZoneSubtype", zone.class.to_s
  end
end
