require_relative 'test_helper'

class ExceptionsTest < Minitest::Test
  DSL_TEXT = <<-ERRORS_DSL
    zone "Cliffs of Error" do
      location "Error Crevasse" do
        agent "guy on fire" do
          define_action "disappear" do
            move_to_instant("closeted cave")
          end

          define_action("bad_intention", "tags" => ["admin"]) do
            action("bad_intention") # To be done immediately
          end

          define_action("bad_notification", "tags" => ["admin"]) do
            notification type: "bad_notification", description: "whoah, something happened!"
          end

          define_action("check no such action") do
            queue_action("no such action")
          end

          on("bad_notification", "re-notify") do |notification|
            notification type: "bad_notification", description: "yet another iteration"
          end
        end
      end
      location "closeted cave" do
        description "Nothing going on here. Nope."
      end
    end
  ERRORS_DSL

  def test_too_many_intention_loops
    engine = Demiurge.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    assert_raises(Demiurge::TooManyIntentionLoopsError) do
      agent_item.queue_action("bad_intention")
      engine.advance_one_tick
    end

  end

  def test_too_many_notification_loops
    engine = Demiurge.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    assert_raises(Demiurge::TooManyNotificationLoopsError) do
      agent_item.queue_action("bad_notification")
      engine.advance_one_tick
    end

  end

  def test_no_such_action
    engine = Demiurge.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    assert_raises(Demiurge::NoSuchActionError) do
      agent_item.queue_action("no such action")
    end

    begin
      agent_item.queue_action("check no such action")
      engine.advance_one_tick
    rescue Demiurge::BadScriptError
      assert_equal "no such action", $!.cause.info["action"]  # Make sure we got the right no-such-action
    end
  end
end
