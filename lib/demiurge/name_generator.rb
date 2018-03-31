module Demiurge; end

require "demiurge/andor_parser"

module Demiurge
  # A Demiurge NameGenerator takes a set of rules for names and
  # creates one or more randomly from that ruleset.
  #
  # @since 0.4.0
  class NameGenerator
    # Regular expression for legal names
    #
    # @since 0.4.0
    NAME_REGEXP = /\A[-_$a-zA-Z0-9]+\Z/

    attr_reader :rules

    # Create a new generator with an empty ruleset
    #
    # @since 0.4.0
    def initialize
      @rules = {}
    end

    # Return all names currently defined by rules.
    #
    # @return [Array<String>] Array of all names.
    # @since 0.4.0
    def names
      @rules.keys
    end

    # Add rules to this generator from the given string
    #
    # @attr [String] rules The block of rule content in DemiRule format.
    # @return [void]
    # @since 0.4.0
    def load_rules_from_andor_string(rules)
      defn_parser = AndorDefnParser.new

      rules.split("\n").each_with_index do |line, line_no|
        content, _ = line.split("#", 2)
        next if content.strip == ""
        name, defn = content.split(":", 2)
        unless name && defn
          raise ::Demiurge::Errors::DemiRuleFormatError.new("Badly-formed name definition line in DemiRule format on line #{line_no.inspect}", "name" => name, "defn" => defn, "line_no" => line_no)
        end
        unless name =~ NAME_REGEXP
          raise ::Demiurge::Errors::DemiRuleFormatError.new("Illegal name #{name.inspect} in DemiRule format on line #{line_no.inspect}", "name" => name, "line_no" => line_no)
        end
        if @rules[name]
          raise ::Demiurge::Errors::DemiRuleFormatError.new("Duplicate name #{name.inspect} in DemiRule format on line #{line_no.inspect}", "name" => name, "line_no" => line_no)
        end

        symbols = defn_parser.parse(defn)

        STDERR.puts "Parser result: #{symbols.inspect}"
        @rules[name] = symbols  # Need to transform to proper ast
      end
      nil
    end

    def generate_from_name(name)
      unless @rules[name]
        raise ::Demiurge::Errors::NoSuchNameInGenerator.new("Unknown name #{name.inspect} in generator!", "name" => name)
      end

      evaluate_ast @rules[name]
    end

    #private

    def evaluate_ast(ast)
      # Let's grow out a Parslet-based evaluator to remove the outdated evaluation code below.
      if ast.is_a?(Hash)
        if ast.has_key?(:str_const)
          return ast[:str_const]
        elsif ast.has_key?(:str_val)
          return ast[:str_val].map { |h| h[:char] }.join
        end
      end

      return generate_from_name(ast[1..-1]) if ast.is_a?(String) && ast[0] == ":"
      return ast if ast.is_a?(String) # And by elimination, the first character was *not* a colon

      raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Malformed rule internal structure!", "ast" => ast.inspect) unless ast.is_a?(Array)

      if ast[0] == "|"
        choices = ast[1..-1]
        probabilities = choices.map { |choice| choice[0] == :prob ? choice[1] : 1.0 }
        total = probabilities.inject(0.0, &:+)
        chosen = rand() * total

        index = 0
        while chosen > probabilities[index] && index < choices.size
          chosen -= probabilities[index]
          index += 1
        end
        STDERR.puts "Chose #{index} / #{choices[index].inspect} from #{choices.inspect}"
        return evaluate_ast choices[index]
      elsif ast[0] == "+"
        return ast[1..-1].map { |elt| evaluate_ast(elt) }.join("")
      elsif ast[0] == :prob
        raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Not supposed to directly evaluate probability rule!", "ast" => ast.inspect)
      else
        raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Malformed rule internal structure: #{ast.inspect}!", "ast" => ast.inspect)
      end
    end

  end

  module Errors
    # This error means there was a problem in DemiRule text supplied to the NameGenerator
    #
    # @since 0.4.0
    class DemiRuleFormatError < AssetError; end

    # This error either means a nonexistent start name was requested to be generated, or a name inside a rule didn't exist.
    #
    # @since 0.4.0
    class NoSuchNameInGenerator < AssetError; end

    # This should only happen if there is an error in NameGenerator itself or the structures are externally manipulated.
    #
    # @since 0.4.0
    class BadlyFormedGeneratorRule < AssetError; end
  end
end
