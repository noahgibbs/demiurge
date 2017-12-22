require_relative 'test_helper'

require "demiurge/dsl"

class QueueingTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "echoing cliffs" do
      location "clifftop" do
        define_action("fake_action2", "tags" => ["admin"]) do
        end

        # Catch "quiet whisper" notifications, re-notify with a series of echoes.
        on("quiet whisper", "re-whisper", zone: "echoing cliffs") do |notif|
          text = notif["text"]
          if text.length > 5
            half_text = text[0...(text.size/2)]
            notification notif.merge(text: half_text)
          end
        end

        on_action("kick colored stones", "block black stones") do |intention|
          intention.cancel("Black stones don't fall down this cliff") if intention.action_args[1] == "black"
        end

        agent "guy on fire" do
          define_action "whisper" do |speech|
            notification type: "quiet whisper", text: speech
          end

          define_action "kick stones", "tags" => ["player_action"] do |how_many|
            notification type: "echoing noise", "stone size": how_many, location: item.location_name
            how_many -= 1
            if how_many > 0
              action "kick stones", how_many
              action "kick stones", how_many
            end
          end

          define_action "kick colored stones", "tags" => ["player_action"] do |how_many, color|
            notification type: "echoing noise", "stone size": how_many, color: color, location: item.location_name
            how_many -= 1
            if how_many > 0
              action "kick colored stones", how_many, "red"
              action "kick colored stones", how_many, "black"
            end
          end
        end
      end
    end
  DSL

  def test_notification_queueing
    engine = Demiurge::DSL.engine_from_dsl_text(["Queueing DSL", DSL_TEXT])

    loc_item = engine.item_by_name("clifftop")

    guy_item = engine.item_by_name("guy on fire")
    assert_equal "clifftop", guy_item.position

    results = []
    engine.subscribe_to_notifications(type: "quiet whisper", location: "clifftop") do |notification|
      results.push notification
    end

    guy_item.run_action("whisper", "Do androids dream of rural electrification?")
    engine.flush_notifications
    assert_equal([
                   "Do androids dream of rural electrification?",
                   "Do androids dream of ",
                   "Do android",
                   "Do an",
                 ],
                 results.map { |r| r["text"] })
  end

  def test_intention_queueing
    engine = Demiurge::DSL.engine_from_dsl_text(["Queueing DSL", DSL_TEXT])

    loc_item = engine.item_by_name("clifftop")
    guy_item = engine.item_by_name("guy on fire")
    assert_equal "clifftop", guy_item.position

    results = []
    engine.subscribe_to_notifications(type: "echoing noise", location: "clifftop") do |notification|
      results.push notification["stone size"]
    end

    guy_item.queue_action("kick stones", 3)
    engine.advance_one_tick

    assert_equal([ 3, 2, 2, 1, 1, 1, 1 ], results)
  end

  def test_intention_queue_and_offers
    engine = Demiurge::DSL.engine_from_dsl_text(["Queueing DSL", DSL_TEXT])

    loc_item = engine.item_by_name("clifftop")
    guy_item = engine.item_by_name("guy on fire")
    assert_equal "clifftop", guy_item.position

    results = []
    engine.subscribe_to_notifications(type: "echoing noise", location: "clifftop") do |notification|
      results.push notification["stone size"]
    end

    guy_item.queue_action("kick colored stones", 4)
    engine.advance_one_tick

    assert_equal([ 4, 3, 2, 1 ], results)
  end
end
