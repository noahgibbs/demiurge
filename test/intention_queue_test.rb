require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

COUNTER_OBJ = { "counter" => 0 }

class IntentionQueueTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "mage city", "type" => "TmxZone" do
      tmx_location "east end" do
        manasource_tile_layout "test/magecity_cc0_lorestrome.tmx"
      end
      agent "wanderer" do
        position "east end#10,10"
        state.slow_actions = 0
        state.fast_actions = 0
        define_action("slow_action", "busy" => 3) do
          state.slow_actions += 1
        end
        every_X_ticks("act", 1) do
          queue_action("slow_action")  # This means we'll have far more of these than we can successfully finish.
          state.fast_actions += 1
        end
      end
    end
  DSL

  def test_stop_on_busy
    engine = Demiurge.engine_from_dsl_text(["Mage City DSL", DSL_TEXT])
    loc = engine.item_by_name("east end")
    refute_nil loc
    agent = engine.item_by_name("wanderer")
    refute_nil agent

    20.times do
      intentions = engine.next_step_intentions
      engine.apply_intentions(intentions)
    end

    # If the mobile stays busy for 3 ticks on each action, 18 ticks
    # should allow time for 6 actions.  Since it starts on tick #1
    # (not tick #0) that means 7 actions in 20 ticks.
    assert_equal 7, agent.state["slow_actions"]
    # Fast actions happen every tick after the very first one. The
    # very first one hasn't yet queued up the intention.
    assert_equal 20, agent.state["fast_actions"]
  end
end
