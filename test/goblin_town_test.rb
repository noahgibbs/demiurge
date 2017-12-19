require_relative 'test_helper'

module GoblinTown
  class MossCave < Demiurge::StateItem
    def initialize(name, engine, state)
      super
      @growmoss_intention = GrowMoss.new(name, engine)
    end

    def intentions_for_next_step()
      @growmoss_intention
    end

    def zone?
      true
    end
  end

  class GrowMoss < Demiurge::Intention
    def initialize(name, engine)
      @name = name
      super(engine)
    end

    def allowed?
      true
    end

    def offer(intention_id)
      # Do nothing
    end

    def apply
      item = @engine.item_by_name(@name)
      item.state["moss"] += 1
      if item.state["moss"] >= item.state["growmoss_every"]
        item.state["grown_moss"] += 1
        item.state["moss"] = 0
      end
    end

  end
end

class GoblinTownTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Demiurge::VERSION
  end

  def test_trivial_non_dsl_actions
    state = [
      ["MossCave", "mosscave1", { "moss" => 0, "growmoss_every" => 3, "grown_moss" => 0 }],
      ["MossCave", "mosscave2", { "moss" => 0, "growmoss_every" => 3, "grown_moss" => 0 }],
    ]
    types = {
      "GrowMoss" => GoblinTown::GrowMoss,
      "MossCave" => GoblinTown::MossCave,
      "InertStateItem" => Demiurge::InertStateItem,
    }
    goblin_town = Demiurge::Engine.new types: types, state: state
    # Normally getting an engine from DSL will automatically call
    # finished_init, but that's not what we do here.  So we do it
    # manually.
    goblin_town.finished_init
    cave = goblin_town.item_by_name("mosscave1")
    assert_equal 0, cave.state["moss"]

    goblin_town.advance_one_tick

    assert_equal 1, cave.state["moss"]

    2.times { goblin_town.advance_one_tick }
    assert_equal 0, cave.state["moss"]
    assert_equal 1, cave.state["grown_moss"]
  end
end
