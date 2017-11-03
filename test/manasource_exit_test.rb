require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

class ManaSourceExitTmxTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "manasource exit test zone", "type" => "TmxZone" do
      tmx_location "room 1" do
        manasource_tile_layout "test/exit_test_1.tmx"
        state.some_var = 7
      end
      tmx_location "room 2" do
        manasource_tile_layout "test/exit_test_2.tmx"
        state.other_var = 7
      end
    end
  DSL

  def test_tmx_manasource_exit_support
    engine = Demiurge.engine_from_dsl_text(["ManaSource Exit Zone DSL", DSL_TEXT])
    loc1 = engine.item_by_name("room 1")
    refute_nil loc1
    loc2 = engine.item_by_name("room 2")
    refute_nil loc2

    assert_equal [{ "from" => "room 1#10,11", "to" => "room 2#12,13", "properties" => {} }], loc1.exits
    assert_equal [{ "from" => "room 2#12,13", "to" => "room 1#8,9", "properties" => {} }], loc2.exits

    intentions = engine.next_step_intentions
    engine.apply_intentions(intentions)
  end
end
