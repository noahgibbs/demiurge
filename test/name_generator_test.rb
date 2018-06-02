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

  def test_simple_quoted_string_escape_rule
    gen = parser_from <<RULES
start: "bobo\\ yes"
RULES
    assert_equal "bobo\\ yes", gen.generate_from_name("start")
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

  def test_simple_two_arg_bar_rule_fixed_randomizer
    gen = parser_from <<RULES
start: :thing1 | "thing two"
thing1: "bob"
RULES
    gen.randomizer = fixed_randomizer
    assert_equal ["bob", "bob", "bob", "bob", "bob", "thing two", "bob", "thing two", "thing two", "bob", "bob", "thing two", "bob", "thing two", "bob", "thing two", "thing two", "bob", "bob", "thing two"], (1..20).map { gen.generate_from_name("start") }
  end

  def test_simple_four_arg_bar_rule
    gen = parser_from <<RULES
start: :thing1 | "thing 2" | :thing_3 | "thing 4"
thing1: "thing1"
thing_3: thing3
RULES
    assert_equal [ "thing 2", "thing 4", "thing1", "thing3" ], (1..200).map { gen.generate_from_name("start") }.uniq.sort
  end

  def test_simple_four_arg_bar_rule_with_one_prob
    gen = parser_from <<RULES
start: :thing1 | "thing 2" | :thing_3 (0.1) | "thing 4"
thing1: "thing1"
thing_3: thing3
RULES
    assert_equal [ "thing 2", "thing 4", "thing1", "thing3" ], (1..200).map { gen.generate_from_name("start") }.uniq.sort
  end

  def test_no_decimal_point_prob
    gen = parser_from <<RULES
start: :thing1 (10) | "thing 2" (10) | :thing_3 | "thing 4" (10)
thing1: "thing1"
thing_3: thing3
RULES
    assert_equal [ "thing 2", "thing 4", "thing1", "thing3" ], (1..200).map { gen.generate_from_name("start") }.uniq.sort
  end

  def test_simple_four_arg_bar_rule_with_one_prob_fixed_randomizer
    gen = parser_from <<RULES
start: :thing1 (0.4) | "thing 2" | :thing_3 (0.1) | "thing 4"
thing1: "thing1"
thing_3: thing3
RULES
    gen.randomizer = fixed_randomizer
    assert_equal ["thing 2", "thing1", "thing 2", "thing 2", "thing 2", "thing 2", "thing 2", "thing 4", "thing 4", "thing1", "thing 2", "thing 4", "thing1", "thing 4", "thing 2", "thing 4", "thing 4", "thing 2", "thing 2", "thing3"], (1..20).map { gen.generate_from_name("start") }
  end

  def test_operator_precedence
    gen = parser_from <<RULES
start: :thing1 | "thing 2" + :thing_3 | "thing 4"
thing1: "thing1"
thing_3: thing3
RULES
    assert_equal [ "thing 2thing3", "thing 4", "thing1" ], (1..200).map { gen.generate_from_name("start") }.uniq.sort
  end

  def test_operator_precedence_fixed_randomizer
    gen = parser_from <<RULES
start: :thing1 | "thing 2" + :thing_3 | "thing 4"
thing1: "thing1"
thing_3: thing3
RULES
    gen.randomizer = fixed_randomizer
    assert_equal ["thing1", "thing1", "thing1", "thing 2thing3", "thing1", "thing 2thing3", "thing1", "thing 4", "thing 4", "thing1", "thing 2thing3", "thing 2thing3", "thing1", "thing 4", "thing 2thing3", "thing 4", "thing 4", "thing 2thing3", "thing 2thing3", "thing 2thing3"], (1..20).map { gen.generate_from_name("start") }
  end

  def test_simple_parens_with_quotes_only
    gen = parser_from <<RULES
start: ("bobo")
RULES
    assert_equal "bobo", gen.generate_from_name("start")
  end

  def test_simple_parens_no_quotes_only
    gen = parser_from <<RULES
start: (bobo)
RULES
    assert_equal "bobo", gen.generate_from_name("start")
  end

  def test_simple_parens_with_inside_ops
    gen = parser_from <<RULES
start: (bobo + :thing)
thing: dyne
RULES
    assert_equal "bobodyne", gen.generate_from_name("start")
  end

  def test_simple_parens_with_outside_ops
    gen = parser_from <<RULES
start: (bobo) + :thing
thing: dyne
RULES
    assert_equal "bobodyne", gen.generate_from_name("start")
  end

  def test_parens_operator_precedence
    gen = parser_from <<RULES
start: (:thing1 | "thing2") + :thing_3 | "thing4"
thing1: "thing1"
thing_3: thing3
RULES
    assert_equal [ "thing1thing3", "thing2thing3", "thing4" ], (1..200).map { gen.generate_from_name("start") }.uniq.sort
  end

  def test_fake_bar_probability
    gen = parser_from <<RULES
start: thing1 | thing1 | thing1 | thing2 | thing3
RULES
    gen.randomizer = fixed_randomizer
    entries = (1..200).map { gen.generate_from_name("start") }
    assert_equal 123, entries.select { |s| s == "thing1" }.size
    assert_equal 48, entries.select { |s| s == "thing2" }.size
    assert_equal 29, entries.select { |s| s == "thing3" }.size
  end

  # "Random testcase" here means "I was doing something and this broke, so let's add a test."
  def test_probability_in_bar_expressions_random_testcase
    gen = parser_from <<RULES
plural_number: two | three | four | five | six (0.5) | seven (0.3) | eight (0.2) | nine (0.1) | ten (0.5) | fifty (0.1) | "a hundred" (0.1)
RULES
    gen.randomizer = fixed_randomizer
    entries = (1..10).map { gen.generate_from_name("plural_number") }
    assert_equal ["three", "two", "three", "four", "three", "five", "three", "fifty", "six", "two"], entries
  end
end
