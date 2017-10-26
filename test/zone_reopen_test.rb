require_relative 'test_helper'

require "demiurge/dsl"

DSL_TEXT_1 = <<GOBLIN_DSL_1
  zone "moss caves" do
    location "first moss cave" do
      description "This cave is dim, with smooth sides. You can see delicious moss growing inside, out of the hot sunlight."
      state.moss = 0

      every_X_ticks("grow", 3) do
        state.moss += 1
        action description: "The moss slowly grows longer and more lush here."
      end
    end

    on("event1", "handler1") do
      STDERR.puts "Sample action 1"
    end
  end
GOBLIN_DSL_1

DSL_TEXT_2 = <<GOBLIN_DSL_2
  zone "moss caves" do
    location "second moss cave" do
      description "A recently-opened cave here has jagged walls, and delicious-looking stubbly moss in between the cracks."
      state.moss = 0

      every_X_ticks("grow", 3) do
        state.moss += 1
        action description: "The moss in the cracks seems to get thicker and softer moment by moment."
      end
    end

    # Comment line to differentiate line numbers in error messages.
    on("event2", "handler2") do
      STDERR.puts "Sample action 2"
    end
  end
GOBLIN_DSL_2

class ZoneReopenTest < Minitest::Test
  def test_zone_reopen
    engine = Demiurge.engine_from_dsl_text(DSL_TEXT_1, DSL_TEXT_2)
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item

    assert_equal 0, engine.state_for_property("first moss cave", "moss")
    assert_equal 0, engine.state_for_property("second moss cave", "moss")
    intentions = engine.next_step_intentions
    assert_equal 2, intentions.size
  end
end
