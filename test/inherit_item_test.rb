require_relative 'test_helper'

require "demiurge/dsl"

class CopyItemTest < Minitest::Test
  DSL_TEXT = <<-GOBLIN_DSL
    zone "moss caves" do
      location "first moss cave" do
        description "This cave is dim, with smooth sides. You can see delicious moss growing inside, out of the hot sunlight."
        state.moss = 0

        every_X_ticks("grow", 3) do
          state.moss += 1
          notification description: "The moss slowly grows longer and more lush here."
        end
      end
    end
  GOBLIN_DSL

  # Oh hey, putting the actions back into the items busted item
  # save/restore.  It means that if the StateItems are destroyed and
  # replaced (say with a state restore) then the actions don't come
  # back.  In general, needing to load procs from world files is bad
  # for state restore (where do procs come from?). It also makes
  # instancing kind of a pain. If we store the actions in the engine
  # again (le sigh) then we only need to have read from World Files
  # once, ever, as long as all actions are put into the engine and can
  # be looked up somehow. Copying or instancing will still need to
  # work by checking a different item's name/entries, though, possibly
  # as a fallback. So it could still basically be prototype
  # inheritance.
  def test_simple_item_copy
    engine = Demiurge.engine_from_dsl_text(["Goblin DSL", DSL_TEXT])
    first_cave_item = engine.item_by_name("first moss cave")
    refute_nil first_cave_item
    zone = engine.item_by_name("moss caves")
    refute_nil zone
    second_cave_item = engine.instantiate_new_item("second moss cave", first_cave_item)
    refute_nil engine.item_by_name("second moss cave")
    assert_equal ["first moss cave", "second moss cave"], zone.location_names.sort

    6.times do
      engine.advance_one_tick
    end

    assert_equal 2, second_cave_item.state["moss"]
    assert_equal 2, first_cave_item.state["moss"]
  end
end
