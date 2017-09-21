require_relative "engine.rb"

module GoblinTown
  class MossCave < Ygg::StateItem
    attr_reader :state

    def initialize(state)
      @state = state
      raise "State should be frozen!" unless state.frozen?
      @growmoss_intention = GrowMoss.new("item_name" => state["name"])
    end

    def intentions_for_next_step(options)
      @growmoss_intention
    end
  end

  class GrowMoss < Ygg::Intention
    INIT_PARAMS = [ "item_name" ]

    def initialize(state)
      illegal_params = state.keys - INIT_PARAMS
      raise "Illegal parameters creating GrowMoss intention: #{illegal_params.inspect}!" unless illegal_params.empty?
      @state = state
    end

    def allowed?(engine, options)
      true
    end

    def apply(engine, options)
      item = engine.item_by_name(@state["item_name"])
      STDERR.puts "Preparing to change state!"
      item.state["moss"] += 1
      if item.state["moss"] >= item.state["growmoss_every"]
        # Okay, now add an intention
	STDERR.puts "We're growing some new moss here."
        item.state["moss"] = 0
      end
    end

  end
end

state = [
  ["MossCave", { "name" => "mosscave1", "moss" => 0, "growmoss_every" => 3 }],
  ["MossCave", { "name" => "mosscave2", "moss" => 0, "growmoss_every" => 3 }],
]

Ygg::StateItem.register_type "GrowMoss", GoblinTown::GrowMoss
Ygg::StateItem.register_type "MossCave", GoblinTown::MossCave

goblin_town = Ygg::StoryEngine.new "state" => state

STDERR.puts "State:\n#{MultiJson.dump goblin_town.structured_state, :pretty => true}"

#File.open("/tmp/statefile", "w") do |f|
#  f.write(MultiJson.dump goblin_town.structured_state, :pretty => true)
#end

intentions = goblin_town.next_step_intentions
STDERR.puts "Intentions: #{intentions.inspect}"

goblin_town.apply_intentions(intentions)
