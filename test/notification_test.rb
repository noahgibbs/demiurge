require_relative 'test_helper'

class NotificationTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "topzone" do
      location "one" do
        on("some event", "my action name") do
          notification type: :dweomer, description: "whoah, something happened!", zone: "otherzone"
        end
      end
    end

    zone "otherzone" do
      location "other one" do; end
      location "other two" do; end
    end
  DSL
  def test_unsubscribe
    engine = Demiurge.engine_from_dsl_text(["Subscription Test DSL", DSL_TEXT])
    loc = engine.item_by_name("topzone")
    refute_nil loc

    my_notifications = []

    engine.subscribe_to_notifications(tracker: :test_unsub) do |*args, **kwargs|
      my_notifications.push(args[0].merge(kwargs))
    end
    assert_equal 0, my_notifications.size

    engine.send_notification(notification_type: "test1", zone: "topzone", location: "one", item_acting: "one")
    engine.flush_notifications
    assert_equal 1, my_notifications.size

    engine.unsubscribe_from_notifications(:test_unsub)
    assert_equal 1, my_notifications.size

    engine.send_notification(notification_type: "test1", zone: "topzone", location: "one", item_acting: "one")
    engine.flush_notifications
    assert_equal 1, my_notifications.size
  end

  def test_basic_subscribe
    engine = Demiurge.engine_from_dsl_text(["Subscription Test DSL", DSL_TEXT])
    loc = engine.item_by_name("one")
    refute_nil loc

    my_notifications = []

    engine.subscribe_to_notifications() do |notification|
      my_notifications.push(notification)
    end

    loc.run_action "my action name" # Queue a notification
    engine.flush_notifications # Send it out

    assert_equal [{"item acting" => "one", "zone" => "otherzone", "type" => "dweomer", "description" => "whoah, something happened!", "location" => "one"}], my_notifications
  end
end
