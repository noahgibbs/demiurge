require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

class SimpleTmxTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "mage city" do
      tmx_location "east end" do
        manasource_tile_layout "test/magecity_cc0_lorestrome.tmx"
        state.some_var = 7
      end
    end
  DSL

  def test_dsl_tmx_support
    engine = Demiurge.engine_from_dsl_text(["Mage City DSL", DSL_TEXT])
    engine.finished_init
    loc = engine.item_by_name("east end")
    refute_nil loc

    intentions = engine.next_step_intentions
    engine.apply_intentions(intentions)
  end
end
