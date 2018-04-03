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
    attr_accessor :randomizer

    # Create a new generator with an empty ruleset
    #
    # @since 0.4.0
    def initialize
      @rules = {}
      @randomizer = Random.new(Time.now.to_i)
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
        next if content == nil
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

        begin
          symbols = defn_parser.parse(defn)
        rescue Parslet::ParseFailed => error
          raise ::Demiurge::Errors::DemiRuleFormatError.new("Can't parse Andor name definition for #{name.inspect}", "definition" => defn, "name" => name, "line_no" => line_no, "error" => error.parse_failure_cause.ascii_tree)
        end

        @rules[name] = symbols  # Need to transform to proper ast
      end
      nil
    end

    def generate_from_name(name)
      unless @rules.has_key?(name)
        STDERR.puts "Known rules: #{@rules.keys.inspect}"
        raise ::Demiurge::Errors::NoSuchNameInGenerator.new("Unknown name #{name.inspect} in generator!", "name" => name)
      end

      evaluate_ast @rules[name], name: name
    end

    #private

    def evaluate_ast(ast, name: "some name")
      # Let's grow out a Parslet-based evaluator to remove the outdated evaluation code below.
      if ast.is_a?(Hash)
        if ast.has_key?(:str_const)
          return ast[:str_const]
        elsif ast.has_key?(:str_val)
          return ast[:str_val].map { |h| h[:char] }.join
        elsif ast.has_key?(:name)
          return generate_from_name(ast[:name].to_s)
        else
          raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Malformed rule internal structure: (Hash) #{ast.inspect}!", "ast" => ast.inspect)
        end
      elsif ast.is_a?(Array)
        if ast[0].has_key?(:left)
          if ast[1].has_key?(:plus)
            left_side = evaluate_ast(ast[0][:left])
            return ast[1..-1].map { |term| evaluate_ast(term[:right]) }.inject(left_side, &:+)
          elsif ast[1].has_key?(:bar)
            left_prob = ast[0][:left_prob] ? ast[0][:left_prob][:prob].to_f : 1.0
            choice_prob = [left_prob] + ast[1..-1].map { |term| term[:right_prob] ? term[:right_prob][:prob].to_f : 1.0 }

            unless choice_prob.all? { |p| p.is_a?(Float) }
              raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Probability isn't a float: #{choice_prob.select { |p| !p.is_a?(Float) }.inspect}!", "ast" => ast.inspect)
            end
            total_prob = choice_prob.inject(0.0, &:+)
            if total_prob < 0.000001
              raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Total probability less than epsilon: #{total_prob.inspect}!", "ast" => ast.inspect)
            end
            r = @randomizer.rand(total_prob)

            # Subtract probability from our random sample until we get that far into the CDF
            cur_index = 0
            while cur_index < choice_prob.size && r >= choice_prob[cur_index]
              r -= choice_prob[cur_index]
              cur_index += 1
            end
            # Shouldn't hit this, but just in case...
            cur_index = (choice_prob.size - 1) if cur_index >= choice_prob.size
            if cur_index == 0
              bar_choice = evaluate_ast(ast[0][:left]).to_s
            else
              bar_choice = evaluate_ast(ast[cur_index][:right]).to_s
            end

            return bar_choice
          else
            raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Malformed rule internal structure: (Array/op) #{ast.inspect}!", "ast" => ast.inspect)
          end
        else
          raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Malformed rule internal structure: (Array) #{ast.inspect}!", "ast" => ast.inspect)
        end
      else
        raise ::Demiurge::Errors::BadlyFormedGeneratorRule.new("Malformed rule internal structure: (#{ast.class}) #{ast.inspect}!", "ast" => ast.inspect)
      end

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
