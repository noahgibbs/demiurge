require_relative 'test_helper'

require "demiurge/dsl"

class DslTest < Minitest::Test
  STATEDUMP_LOCATION = {}
  DSL_TEXT = <<-FIRE_DSL
    inert "config_settings"
    zone "fire caves" do
      location "flaming cave" do
        define_action("mem_statedump", "engine_code" => true, "tags" => ["admin"]) do
          config = engine.item_by_name("config_settings")
          config.state["bobo"] = "yup"
          ss = engine.structured_state
          ::DslTest::STATEDUMP_LOCATION["ss"] = ss
        end

        agent "guy on fire" do
          define_action "disappear" do
            teleport_instant("closeted cave")
          end

          define_action "file_statedump" do
            dump_state("somedir/myfile.json")
          end
        end
      end
      location "closeted cave" do
        description "Nothing going on here. Nope."
      end
    end
  FIRE_DSL

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
  end

end
