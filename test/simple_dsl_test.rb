require_relative 'test_helper'

require "demiurge/dsl"

DSL_TEXT = <<GOBLIN_DSL
  zone "moss caves" do
    location "first moss cave" do
      description "This cave is dim, with smooth sides. You can see delicious moss growing inside, out of the hot sunlight."
      state.moss = 0

      every_X_ticks("grow", 3) do
        state.moss += 1
        action description: "The moss slowly grows longer and more lush here."
      end
    end

    location "second moss cave" do
      description "A recently-opened cave here has jagged walls, and delicious-looking stubbly moss in between the cracks."
      state.moss = 0

      every_X_ticks("grow", 3) do
        state.moss += 1
        action description: "The moss in the cracks seems to get thicker and softer moment by moment."
      end
    end
  end

  #player do
  #  start_zone "moss caves"
  #end
GOBLIN_DSL

class SimpleDslTest < Minitest::Test
  def test_trivial_dsl_actions
    engine = Demiurge.engine_from_dsl_text(DSL_TEXT)

    intentions = engine.next_step_intentions

    engine.apply_intentions(intentions)

    intentions = engine.next_step_intentions
    engine.apply_intentions(intentions)
    intentions = engine.next_step_intentions
    engine.apply_intentions(intentions)
  end
end
