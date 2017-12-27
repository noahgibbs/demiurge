require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

COUNTER_OBJ = { "counter" => 0 }

class IntentionQueueTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "mage city", "type" => "TmxZone" do
      tmx_location "east end" do
        manasource_tile_layout "test/data/magecity_cc0_lorestrome.tmx"
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

      location("one") do
        agent("standing still") do
          state.feeling_it = false
          define_action("maybe move") do
            cancel_intention("Nope, don't feel like it.") unless state.feeling_it
            move_to_instant("two")
            state.feeling_it = false
          end
          define_action("get inspired") do
            state.feeling_it = true
          end
        end
      end

      location("two") do
      end
    end
  DSL

  def test_stop_on_busy
    engine = Demiurge::DSL.engine_from_dsl_text(["Mage City DSL", DSL_TEXT])
    loc = engine.item_by_name("east end")
    refute_nil loc
    agent = engine.item_by_name("wanderer")
    refute_nil agent

    20.times do
      engine.advance_one_tick
    end

    # If the mobile stays busy for 3 ticks on each action, 18 ticks
    # should allow time for 6 actions.  Since it starts on tick #1
    # (not tick #0) that means 7 actions in 20 ticks.
    assert_equal 7, agent.state["slow_actions"]
    # Fast actions happen every tick after the very first one. The
    # very first one hasn't yet queued up the intention.
    assert_equal 20, agent.state["fast_actions"]
  end

  def test_cancel_intention
    engine = Demiurge::DSL.engine_from_dsl_text(["Cancel Intention DSL", DSL_TEXT])
    agent = engine.item_by_name("standing still")
    confirmations = []
    engine.subscribe_to_notifications(type: [ Demiurge::Notifications::IntentionCancelled, Demiurge::Notifications::IntentionApplied ], actor: "standing still") do |notification|
      confirmations.push([ notification["type"], notification["reason"], notification["queue_number"] ])
    end

    engine.flush_notifications
    assert_equal [], confirmations
    queue_num = agent.queue_action("maybe move")
    engine.advance_one_tick
    # Make sure we got only a cancel from a queued action that failed, and no confirmation
    assert_equal [ [Demiurge::Notifications::IntentionCancelled, "Nope, don't feel like it.", queue_num ] ], confirmations
    confirmations.pop

    # Make sure we get no cancel and no confirmation with run_action, which doesn't create an intention
    agent.run_action("get inspired")
    assert_equal [], confirmations
    agent.run_action("maybe move")
    assert_equal [], confirmations
  end

  def test_action_queue_number
    engine = Demiurge::DSL.engine_from_dsl_text(["Cancel Intention DSL", DSL_TEXT])
    agent = engine.item_by_name("standing still")
    confirmations = []
    engine.subscribe_to_notifications(actor: "standing still", type: [ Demiurge::Notifications::IntentionCancelled, Demiurge::Notifications::IntentionApplied ]) do |notification|
      confirmations.push([ notification["type"], notification["reason"], notification["queue_number"] ])
    end

    engine.flush_notifications
    assert_equal [], confirmations

    cancelled_queue_num = agent.queue_action("maybe move")
    engine.advance_one_tick
    assert_equal [ [Demiurge::Notifications::IntentionCancelled, "Nope, don't feel like it.", cancelled_queue_num ] ], confirmations

    agent.run_action("get inspired") # No cancel or apply notification
    applied_queue_num = agent.queue_action("maybe move")
    engine.advance_one_tick
    assert_equal [[Demiurge::Notifications::IntentionCancelled, "Nope, don't feel like it.", cancelled_queue_num ],
                  [Demiurge::Notifications::IntentionApplied, nil, applied_queue_num ]], confirmations
  end
end
