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

    every_X_ticks("first_every", 1) do
      # Nothing interesting
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

    every_X_ticks("second_every", 3) do
      # Nothing interesting
    end
  end
GOBLIN_DSL_2

class ZoneReopenTest < Minitest::Test
  def test_zone_reopen
    engine = Demiurge.engine_from_dsl_text(DSL_TEXT_1, DSL_TEXT_2)
    first_cave_item = engine.item_by_name("first moss cave")
    refute_nil first_cave_item
    second_cave_item = engine.item_by_name("second moss cave")
    refute_nil second_cave_item

    zone = engine.item_by_name("moss caves")
    assert_equal ["event1", "event2"], zone.state["on_handlers"].keys.sort
    assert_equal [{"action" => "first_every", "every"=>1, "counter"=>0}, {"action"=>"second_every", "every"=>3, "counter"=>0}], zone.state["everies"]

    assert_equal 0, first_cave_item.state["moss"]
    assert_equal 0, second_cave_item.state["moss"]
    intentions = engine.next_step_intentions
    assert_equal 2, intentions.size
  end
end
