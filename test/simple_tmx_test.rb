require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

class SimpleTmxTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "mage city" do
      tmx_location "east end" do
        manasource_tile_layout "test/data/magecity_cc0_lorestrome.tmx"
        state.some_var = 7
      end
    end
  DSL

  def test_dsl_tmx_support
    engine = Demiurge::DSL.engine_from_dsl_text(["Mage City DSL", DSL_TEXT])
    loc = engine.item_by_name("east end")
    refute_nil loc
    x, y = loc.tmx_object_coords_by_name("waypoint 1")
    assert_equal [9, 11], [x, y]

    engine.advance_one_tick
  end
end
