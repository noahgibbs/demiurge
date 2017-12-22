require_relative 'test_helper'

require "demiurge/dsl"
require "demiurge/tmx"

class PositioningTest < Minitest::Test
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

          define_action("moveto") do |x, y|
            move_to_instant "\#{item.location_name}#\#{x},\#{y}"
          end

          define_action("move_to_position") do |pos|
            move_to_instant pos
          end
        end
      end

      tmx_location "room_exits_sw" do
        manasource_tile_layout "test/data/ms_room_exits_sw.tmx"
      end

      location "nontmx" do
        description "Yup, a lonely old-style room..."
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
    engine = Demiurge::DSL.engine_from_dsl_text(["Positioning DSL", DSL_TEXT])
    loc = engine.item_by_name("east end")
    refute_nil loc

    zone = engine.item_by_name("pathfinder city")
    refute_nil zone

    assert_equal [[9,4],[8,5]], zone.adjacent_positions("east end#8,4")
  end

  def test_tmx_position_movement
    engine = Demiurge::DSL.engine_from_dsl_text(["Positioning DSL", DSL_TEXT])
    agent = engine.item_by_name("MoveTester")
    refute_nil agent

    cancellations = []
    engine.subscribe_to_notifications(type: "intention_cancelled") do |n|
      cancellations.push(n)
    end
    assert_equal 0, cancellations.size
    assert_equal "room_exits_se#3,3", agent.position
    assert_equal "room_exits_se", agent.location_name
    assert_equal "pathfinder city", agent.zone_name
    agent.move_to_position("room_exits_se#6,6")

    agent.queue_action("moveto", 6, 7)
    agent.queue_action("moveto", 6, 8)
    engine.advance_one_tick
    assert_equal "room_exits_se#6,7", agent.position
    engine.advance_one_tick
    assert_equal "room_exits_se#6,8", agent.position
    assert_equal 0, cancellations.size
  end

  def test_tmx_exit_movement
    engine = Demiurge::DSL.engine_from_dsl_text(["Positioning DSL", DSL_TEXT])
    agent = engine.item_by_name("MoveTester")
    refute_nil agent

    cancellations = []
    engine.subscribe_to_notifications(type: "intention_cancelled") do |n|
      cancellations.push(n)
    end
    assert_equal 0, cancellations.size
    assert_equal "room_exits_se#3,3", agent.position

    # Go through the east exit
    agent.queue_action("moveto", 18, 10)
    engine.advance_one_tick
    assert_equal 0, cancellations.size
    assert_equal "room_exits_sw#2,10", agent.position
  end

  def test_tmx_blocked_movement
    engine = Demiurge::DSL.engine_from_dsl_text(["Positioning DSL", DSL_TEXT])
    agent = engine.item_by_name("MoveTester")
    refute_nil agent

    cancellations = []
    engine.subscribe_to_notifications(type: "intention_cancelled") do |n|
      cancellations.push(n)
    end
    assert_equal 0, cancellations.size
    assert_equal "room_exits_se#3,3", agent.position

    # Go to an illegal position
    agent.queue_action("moveto", 0, 3)
    engine.advance_one_tick
    assert_equal 1, cancellations.size
    assert_equal "room_exits_se#3,3", agent.position
  end

  def test_tmx_and_room_movement
    engine = Demiurge::DSL.engine_from_dsl_text(["Positioning DSL", DSL_TEXT])
    agent = engine.item_by_name("MoveTester")
    refute_nil agent

    cancellations = []
    engine.subscribe_to_notifications(type: "intention_cancelled") do |n|
      cancellations.push(n)
    end
    assert_equal 0, cancellations.size
    assert_equal "room_exits_se#3,3", agent.position

    # Move to a non-TMX room
    agent.queue_action("move_to_position", "nontmx")
    engine.advance_one_tick
    assert_equal 0, cancellations.size
    assert_equal "nontmx", agent.position

    # Move back into TMX rooms
    agent.queue_action("move_to_position", "room_exits_sw#7,4")
    agent.queue_action("move_to_position", "room_exits_ne#9,8")
    engine.advance_one_tick
    assert_equal "room_exits_sw#7,4", agent.position
    engine.advance_one_tick
    assert_equal "room_exits_ne#9,8", agent.position
    assert_equal 0, cancellations.size

    assert_engine_sanity_check_contents(engine)
  end

  def test_various_location_transitions
    # This list of positions will test a number of transitions:
    queueable_position_list = [
      # Implicit start for agent: room_exits_se#3,3
      "nontmx",                        # TMX to same-zone non-TMX
      "room_exits_nw#11,11",           # Non-TMX to same-zone TMX
      "east end#4,4",                  # TMX to other-zone TMX
      "nontmx",                        # TMX to other-zone non-TMX
      "empty room",                    # Non-TMX to other-zone non-TMX
      "pathfinder city",               # Non-TMX to other top-level Zone (not a sub-location) and have to stop...
    ]
    # If you're moving from top-level zones, the agent won't receive a tick so it can't use a queueable action.
    nonqueueable_position_list = [
      # Implicit start: pathfinder city (last entry in queueable_position_list)
      "other test zone",               # One top-level zone to another top-level Zone
      "room_exits_se#7,7",             # Top-level zone to other-zone TMX
      "other test zone", "nontmx",     # Top-level zone to other-zone non-TMX
      "other test zone", "east end#4,4",    # Top-level zone to same-zone TMX
      "other test zone", "empty room",      # Top-level zone to same-zone non-TMX
    ]

    engine = Demiurge::DSL.engine_from_dsl_text(["Positioning DSL", DSL_TEXT])
    agent = engine.item_by_name("MoveTester")
    refute_nil agent
    assert_equal "room_exits_se#3,3", agent.position

    cancellations = []
    engine.subscribe_to_notifications(type: "intention_cancelled") do |n|
      cancellations.push(n)
    end
    assert_equal 0, cancellations.size

    queueable_position_list.each do |position|
      last_position = agent.position
      agent.queue_action("move_to_position", position)
      engine.advance_one_tick
      assert_engine_sanity_check_contents(engine)
      assert_equal 0, cancellations.size
      assert position == agent.position, "Got wrong agent position (#{agent.position.inspect}) when transitioning from #{last_position.inspect} to #{position.inspect}... But didn't see a cancellation!"
    end

    nonqueueable_position_list.each do |position|
      last_position = agent.position
      agent.run_action("move_to_position", position)  # Agents don't get a tick in top-level zones, so run the action directly
      assert_engine_sanity_check_contents(engine)
      assert position == agent.position, "Got wrong agent position (#{agent.position.inspect}) when transitioning from #{last_position.inspect} to #{position.inspect} using non-queue transitions..."
    end
    assert_equal 0, cancellations.size
  end

  # Make sure that a queued intention in an agent does *not* happen
  # when the agent is in a normal top-level zone, which shouldn't
  # allow the agent to act.
  def test_no_agent_tick_in_top_level_zones
    engine = Demiurge::DSL.engine_from_dsl_text(["Positioning DSL", DSL_TEXT])
    agent = engine.item_by_name("MoveTester")
    refute_nil agent

    cancellations = []
    engine.subscribe_to_notifications(type: "intention_cancelled") do |n|
      cancellations.push(n)
    end
    assert_equal 0, cancellations.size

    # Either movement *or* a cancellation from the agent means that it
    # got to set an intention. In either case, it acted when it
    # shouldn't have.
    agent.move_to_position("other test zone")  # Move into a top-level zone
    agent.queue_action("move_to_position", "nontmx")
    engine.advance_one_tick
    assert_equal 0, cancellations.size
    assert_equal "other test zone", agent.position
  end
end
