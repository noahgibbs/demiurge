require_relative 'test_helper'

module GoblinTown
  class MossCave < Demiurge::StateItem
    def initialize(name, engine)
      super
      @growmoss_intention = GrowMoss.new(name)
    end

    def intentions_for_next_step(options)
      @growmoss_intention
    end

    def zone?
      true
    end
  end

  class GrowMoss < Demiurge::Intention
    def initialize(name)
      @name = name
    end

    def allowed?(engine, options)
      true
    end

    def apply(engine, options)
      engine.set_state_for_property(@name, "moss", engine.state_for_property(@name, "moss") + 1)
      if engine.state_for_property(@name, "moss") >= engine.state_for_property(@name, "growmoss_every")
        engine.set_state_for_property(@name, "moss", 0)
      end
    end

  end
end

class DemiurgeTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Demiurge::VERSION
  end

  def test_it_does_something_useful
    state = [
      ["MossCave", "mosscave1", { "moss" => 0, "growmoss_every" => 3 }],
      ["MossCave", "mosscave2", { "moss" => 0, "growmoss_every" => 3 }],
    ]
    types = {
      "GrowMoss" => GoblinTown::GrowMoss,
      "MossCave" => GoblinTown::MossCave,
    }
    goblin_town = Demiurge::Engine.new types: types, state: state
    assert_equal 0, goblin_town.state_for_property("mosscave1", "moss")
    intentions = goblin_town.next_step_intentions
    assert_equal 2, intentions.size
    assert intentions[0].is_a?(GoblinTown::GrowMoss)
    assert intentions[1].is_a?(GoblinTown::GrowMoss)
    goblin_town.apply_intentions(intentions)
  end
end
