require_relative "test_helper"

require "demiurge"
require "demiurge/name_generator"

# TODO: test all exceptions

class NameGeneratorTest < Minitest::Test
  def test_simple_string_rule
    gen = Demiurge::NameGenerator.new
    gen.load_rules_from_andor_string <<RULES
start: bobo
RULES
    assert_equal "bobo", gen.generate_from_name("start")
  end

  def test_quoted_string_rule
    gen = Demiurge::NameGenerator.new
    gen.load_rules_from_andor_string <<RULES
start: "frodo"
RULES
    assert_equal "frodo", gen.generate_from_name("start")
  end
end
