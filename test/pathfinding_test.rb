require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

class PathfindingTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "mage city", "type" => "TmxZone" do
      tmx_location "east end" do
        manasource_tile_layout "test/data/magecity_cc0_lorestrome.tmx"
        state.some_var = 7
      end
    end
  DSL

  def test_positions
    engine = Demiurge.engine_from_dsl_text(["Mage City DSL", DSL_TEXT])
    loc = engine.item_by_name("east end")
    refute_nil loc

    zone = engine.item_by_name("mage city")
    refute_nil zone

    assert_equal [[9,4],[8,5]], zone.adjacent_positions("east end#8,4")
  end
end
