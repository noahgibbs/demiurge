require_relative 'test_helper'

class ExceptionsTest < Minitest::Test
  DSL_TEXT = <<-ERRORS_DSL
    zone "Cliffs of Error" do
      location "Error Crevasse" do
        agent "guy on fire" do
          define_action "disappear" do
            move_to_instant("closeted cave")
          end

          define_action("bad_intention", "tags" => ["admin"]) do
            action("bad_intention") # To be done immediately
          end
        end
      end
      location "closeted cave" do
        description "Nothing going on here. Nope."
      end
    end
  ERRORS_DSL

  def test_too_many_intention_loops
    engine = Demiurge.engine_from_dsl_text(["Exceptions DSL", DSL_TEXT])

    agent_item = engine.item_by_name("guy on fire")

    assert_raises(Demiurge::TooManyIntentionLoopsError) do
      agent_item.queue_action("bad_intention")
      engine.advance_one_tick
    end

  end

end
