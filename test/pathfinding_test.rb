require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

class PathfindingTest < Minitest::Test
  DSL_TEXT = <<-DSL
    zone "pathfinder city", "type" => "TmxZone" do
      tmx_location "room_exits_ne" do
        manasource_tile_layout "test/data/ms_room_exits_ne.tmx"
      end

      tmx_location "room_exits_nw" do
        manasource_tile_layout "test/data/ms_room_exits_nw.tmx"
      end

      tmx_location "room_exits_se" do
        manasource_tile_layout "test/data/ms_room_exits_se.tmx"
        agent "MoveTester" do
          position "room_exits_se#3,3"
        end
      end

      tmx_location "room_exits_sw" do
        manasource_tile_layout "test/data/ms_room_exits_sw.tmx"
      end
    end

    zone "other test zone", "type" => "TmxZone" do
      tmx_location "east end" do
        manasource_tile_layout "test/data/magecity_cc0_lorestrome.tmx"
        state.some_var = 7
      end

      # Non-TMX location for testing
      location "empty room" do
        description "Nope, nothing here."
      end
    end
  DSL

  def test_adjacent_positions
    engine = Demiurge.engine_from_dsl_text(["Pathfinding DSL", DSL_TEXT])
    loc = engine.item_by_name("east end")
    refute_nil loc

    zone = engine.item_by_name("pathfinder city")
    refute_nil zone

    assert_equal [[9,4],[8,5]], zone.adjacent_positions("east end#8,4")
  end

  def test_tmx_position_movement
    engine = Demiurge.engine_from_dsl_text(["Pathfinding DSL", DSL_TEXT])
    agent = engine.item_by_name("MoveTester")
    refute_nil agent

    assert_equal "room_exits_se#3,3", agent.position
    assert_equal "room_exits_se", agent.location_name
    assert_equal "pathfinder city", agent.zone_name
    agent.move_to_position("room_exits_se#6,6")
  end

  #def test_tmx_exit_movement
  #  engine = Demiurge.engine_from_dsl_text(["Pathfinding DSL", DSL_TEXT])
  #  agent = engine.item_by_name("MoveTester")
  #  refute_nil agent
  #end
end
