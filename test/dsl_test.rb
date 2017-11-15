require_relative 'test_helper'

require "demiurge/dsl"

class DslTest < Minitest::Test
  STATEDUMP_LOCATION = {}
  DSL_TEXT = <<-FIRE_DSL
    inert "config_settings"
    zone "fire caves" do
      location "flaming cave" do
        define_action("mem_statedump", "engine_code" => true, "tags" => ["admin", "player_action"]) do
          config = engine.item_by_name("config_settings")
          config.state["bobo"] = "yup"
          ss = engine.structured_state
          ::DslTest::STATEDUMP_LOCATION["ss"] = ss
        end

        define_action "room_thought" do |thought|
          notification type: "room_thought", thought: thought
        end

        define_action("fake_action1", "tags" => ["player_action"]) do
        end

        define_action("fake_action2", "tags" => ["admin"]) do
        end

        agent "guy on fire" do
          define_action "disappear" do
            teleport_instant("closeted cave")
          end

          define_action "file_statedump" do
            dump_state("somedir/myfile.json")
          end

          define_action "say" do |speech|
            notification type: "speech", words: speech
          end
        end
      end
      location "closeted cave" do
        description "Nothing going on here. Nope."
      end
    end
  FIRE_DSL

  def test_action_tags
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", DSL_TEXT])
    loc_item = engine.item_by_name("flaming cave")
    assert_equal [ "fake_action2", "mem_statedump" ], loc_item.get_actions_with_tags("admin").map { |a| a["name"] }.sort
    assert_equal [ "fake_action1", "mem_statedump" ], loc_item.get_actions_with_tags(["player_action"]).map { |a| a["name"] }.sort
    assert_equal [ "mem_statedump" ], loc_item.get_actions_with_tags(["admin", "player_action"]).map { |a| a["name"] }
  end

  def test_more_dsl_actions
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", DSL_TEXT])

    settings_item = engine.item_by_name("config_settings")
    refute_nil settings_item

    loc_item = engine.item_by_name("flaming cave")
    loc_item.run_action("mem_statedump")

    refute_nil STATEDUMP_LOCATION["ss"]
    settings_dump_item = STATEDUMP_LOCATION["ss"].detect { |item| item[1] == "config_settings" }
    assert_equal "yup", settings_dump_item[2]["bobo"]

    guy_item = engine.item_by_name("guy on fire")
    assert_equal "flaming cave", guy_item.position
    guy_item.run_action("disappear")
    assert_equal "closeted cave", guy_item.position

    # This won't test what gets *written* to the file, though.
    File.stub :open, true do
      guy_item.run_action("file_statedump")
    end

    engine.flush_notifications # Don't send out notification about the 'disappear' action
    results = []
    engine.subscribe_to_notifications(item_acting: ["guy on fire", "flaming cave"]) do |notification|
      results.push notification
    end

    loc_item.run_action("room_thought", "do fish breathe?")
    engine.flush_notifications
    assert_hash_contains_fields({ "thought" => "do fish breathe?", "type" => "room_thought", "zone" => "fire caves", "location" => "flaming cave", "item acting" => "flaming cave" }, results[0])
    assert_equal 1, results.size
    results.pop
    guy_item.queue_action("say", "hello, there!")
    engine.advance_one_tick
    assert_equal 1, results.size
    assert_hash_contains_fields({ "words" => "hello, there!", "type" => "speech", "zone" => "fire caves", "location" => "closeted cave", "item acting" => "guy on fire" }, results[0])
  end

end
