require "demiurge"

module GoblinTown
  class MossCave < Demiurge::StateItem
    def initialize(name, engine)
      super
      @growmoss_intention = GrowMoss.new(name)
    end

    def intentions_for_next_step(options)
      @growmoss_intention
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
      STDERR.puts "Preparing to change state!"
      engine.set_state_for_property(@name, "moss", engine.state_for_property(@name, "moss") + 1)
      if engine.state_for_property(@name, "moss") >= engine.state_for_property(@name, "growmoss_every")
	STDERR.puts "We're growing some new moss here."
        engine.set_state_for_property(@name, "moss", 0)
      end
    end

  end
end

state = [
  ["MossCave", "mosscave1", { "moss" => 0, "growmoss_every" => 3 }],
  ["MossCave", "mosscave2", { "moss" => 0, "growmoss_every" => 3 }],
]

types = {
  "GrowMoss" => GoblinTown::GrowMoss,
  "MossCave" => GoblinTown::MossCave,
}

goblin_town = Demiurge::Engine.new types: types, state: state

STDERR.puts "State:\n#{MultiJson.dump goblin_town.structured_state, :pretty => true}"

#File.open("/tmp/statefile", "w") do |f|
#  f.write(MultiJson.dump goblin_town.structured_state, :pretty => true)
#end

intentions = goblin_town.next_step_intentions
STDERR.puts "Intentions: #{intentions.inspect}"

goblin_town.apply_intentions(intentions)

STDERR.puts "State:\n#{MultiJson.dump goblin_town.structured_state, :pretty => true}"
