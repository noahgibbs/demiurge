require_relative 'test_helper'

class NotificationTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "topzone" do
      location "one" do
        define_action("my action name") do
          notification type: :dweomer, description: "whoah, something happened!", zone: "otherzone"
        end
      end
    end

    zone "otherzone" do
      location "other one" do
        define_action("other action") do
        end
      end
      location "other two" do; end
    end
  DSL
  def test_unsubscribe
    engine = Demiurge::DSL.engine_from_dsl_text(["Subscription Test DSL", DSL_TEXT])
    loc = engine.item_by_name("topzone")
    refute_nil loc

    my_notifications = []

    engine.subscribe_to_notifications(tracker: :test_unsub) do |*args, **kwargs|
      my_notifications.push(args[0].merge(kwargs))
    end
    assert_equal 0, my_notifications.size

    engine.send_notification(type: "test1", zone: "topzone", location: "one", actor: "one")
    engine.flush_notifications
    assert_equal 1, my_notifications.size

    engine.unsubscribe_from_notifications(:test_unsub)
    assert_equal 1, my_notifications.size

    engine.send_notification(type: "test1", zone: "topzone", location: "one", actor: "one")
    engine.flush_notifications
    assert_equal 1, my_notifications.size
  end

  def test_basic_subscribe
    engine = Demiurge::DSL.engine_from_dsl_text(["Subscription Test DSL", DSL_TEXT])
    loc = engine.item_by_name("one")
    refute_nil loc

    my_notifications = []

    engine.subscribe_to_notifications() do |notification|
      my_notifications.push(notification)
    end

    loc.run_action "my action name" # Queue a notification
    engine.flush_notifications # Send it out

    assert_equal 1, my_notifications.length
    assert_hash_contains_fields({"actor" => "one", "zone" => "otherzone", "type" => "dweomer", "description" => "whoah, something happened!", "location" => "one"}, my_notifications[0])
  end

  def test_modified_subscribe
    engine = Demiurge::DSL.engine_from_dsl_text(["Subscription Test DSL", DSL_TEXT])
    loc_one = engine.item_by_name("one")
    refute_nil loc_one
    loc_other_one = engine.item_by_name("other one")
    refute_nil loc_other_one

    my_notifications = []

    engine.subscribe_to_notifications(actor: "one", tracker: :to_unsub_1) do |notification|
      my_notifications.push(notification)
    end

    loc_one.run_action "my action name" # Queue a notification
    engine.flush_notifications # Send it out

    assert_hash_contains_fields({"actor" => "one", "zone" => "otherzone", "type" => "dweomer", "description" => "whoah, something happened!", "location" => "one"}, my_notifications[0])
    assert_equal 1, my_notifications.size
    engine.unsubscribe_from_notifications(:to_unsub_1)

    my_notifications = []
    engine.subscribe_to_notifications(actor: "other one", tracker: :to_unsub_1) do |notification|
      my_notifications.push(notification)
    end

    loc_one.run_action "my action name" # Queue a notification
    engine.flush_notifications # Send it out

    assert_equal [], my_notifications
    engine.unsubscribe_from_notifications(:to_unsub_1)
  end
end
