require_relative 'test_helper'

class ExceptionsTest < Minitest::Test
  DSL_TEXT = <<-ERRORS_DSL
    zone "Cliffs of Error" do
      location "Error Crevasse" do
        agent "guy on fire" do
          state.some_key = 1

          define_action "disappear" do
            move_to_instant("closeted cave")
          end

          define_action("bad_intention", "tags" => ["admin"]) do
            action("bad_intention") # To be done immediately
          end

          define_action("undefined body action", "tags" => ["admin"])

          define_action("bad_notification", "tags" => ["admin"]) do
            notification type: "bad_notification", description: "whoah, something happened!"
          end

          define_action("check no such action") do
            queue_action("no such action")
          end

          define_action("no such key test") do
            state["no such key"]
          end

          on("bad_notification", "re-notify") do |notification|
            notification type: "bad_notification", description: "yet another iteration"
          end

          define_action("cancel intention") do
            cancel_intention "For no real reason"
          end
        end
      end
      location "closeted cave" do
        description "Nothing going on here. Nope."
      end
    end
  ERRORS_DSL

  def test_too_many_intention_loops
    engine = Demiurge::DSL.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    assert_raises(Demiurge::Errors::TooManyIntentionLoopsError) do
      agent_item.queue_action("bad_intention")
      engine.advance_one_tick
    end

  end

  def test_too_many_notification_loops
    engine = Demiurge::DSL.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    assert_raises(Demiurge::Errors::TooManyNotificationLoopsError) do
      agent_item.queue_action("bad_notification")
      engine.advance_one_tick
    end

  end

  def test_no_such_action
    engine = Demiurge::DSL.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    assert_raises(Demiurge::Errors::NoSuchActionError) do
      agent_item.queue_action("no such action")
    end

    assert_raises(Demiurge::Errors::NoSuchActionError) do
      agent_item.run_action("no such action")
    end

    begin
      agent_item.queue_action("check no such action")
      engine.advance_one_tick
    rescue Demiurge::Errors::BadScriptError
      assert_equal "no such action", $!.cause.info["action"]  # Make sure we got the right no-such-action
    end

    begin
      agent_item.run_action("undefined body action")
    rescue Demiurge::Errors::NoSuchActionError
      assert $!.message["was never defined"], "NoSuchActionError message should contain 'was never defined' for a never-defined action!"
    end
  end

  def test_no_such_agent
    engine = Demiurge::DSL.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    assert_raises(Demiurge::Errors::NoSuchAgentError) do
      Demiurge::AgentInternal::AgentActionIntention.new "no such agent", engine
    end
  end

  def test_no_such_state_key
    engine = Demiurge::DSL.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    begin
      agent_item.queue_action("no such key test")
      engine.advance_one_tick
    rescue ::Demiurge::Errors::BadScriptError
      assert_equal ::Demiurge::Errors::NoSuchStateKeyError, $!.cause.class
    end
  end

  def test_no_current_intention
    engine = Demiurge::DSL.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    begin
      agent_item.run_action("cancel intention")
    rescue Demiurge::Errors::BadScriptError
      assert_equal ::Demiurge::Errors::NoCurrentIntentionError, $!.cause.class
    end
  end
end
