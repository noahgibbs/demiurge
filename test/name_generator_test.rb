require_relative "test_helper"

require "demiurge"
require "demiurge/name_generator"

# TODO: test all exceptions

class NameGeneratorTest < Minitest::Test
  def parser_from(str)
    gen = Demiurge::NameGenerator.new
    gen.load_rules_from_andor_string str
    gen
  end

  def fixed_randomizer
    Random.new(1337)
  end

  def test_simple_string_rule
    gen = parser_from <<RULES
start: bobo
RULES
    assert_equal "bobo", gen.generate_from_name("start")
  end

  def test_simple_quoted_string_rule
    gen = parser_from <<RULES
start: "frodo"
RULES
    assert_equal "frodo", gen.generate_from_name("start")
  end

  def test_simple_name_rule
    gen = parser_from <<RULES
start: :other_sym
other_sym: "big % bob"
RULES
    assert_equal "big % bob", gen.generate_from_name("start")
  end

  def test_simple_two_arg_plus_rule
    gen = parser_from <<RULES
# Trailing space is on purpose to test parsing - one inside quotes, one outside.
start: :other_sym + " is a big " 
other_sym: "big % bob"
RULES
    assert_equal "big % bob is a big ", gen.generate_from_name("start")
  end

  def test_simple_three_arg_plus_rule
    gen = parser_from <<RULES
start: :other_sym + " is a big " + :title
other_sym: "big % bob"
title: meanie
RULES
    assert_equal "big % bob is a big meanie", gen.generate_from_name("start")
  end

  def test_simple_two_arg_bar_rule
    gen = parser_from <<RULES
start: :thing1 | "thing two"
thing1: "bob"
RULES
    assert_equal [ "bob", "thing two" ], (1..100).map { gen.generate_from_name("start") }.uniq.sort
  end

  def test_simple_two_arg_bar_rule_zero_randomizer
    gen = parser_from <<RULES
start: :thing1 | "thing two"
thing1: "bob"
RULES
    gen.randomizer = fixed_randomizer
    assert_equal ["thing two", "thing two", "bob", "bob", "thing two", "thing two", "thing two", "bob", "bob", "bob", "bob", "bob", "thing two", "bob", "bob", "bob", "thing two", "bob", "thing two", "thing two"], (1..20).map { gen.generate_from_name("start") }
  end
end
