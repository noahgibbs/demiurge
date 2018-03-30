module Demiurge
  # A Demiurge NameGenerator takes a set of rules for names and
  # creates one or more randomly from that ruleset.
  #
  # DemiRule format consists of many lines delimited by newline
  # characters. All characters following a pound sign are comments,
  # while lines beginning with a symbol and a colon are name
  # definitions. A line may also consist only of zero or more
  # whitespace characters after comments are removed, and will be
  # ignored. A name is case-sensitive and may consist of alphanumeric
  # characters as well as dollar signs, underscores, and minus
  # signs. After the colon in a name definition is a series of terms
  # telling how to generate that name. A vertical bar means "choose
  # between" while a plus sign means "concatenate".  Both operators
  # work left-to-right, and plus has a higher operator precedence than
  # vertical bar. Parentheses may be used to explicitly specify
  # operation order. Double-quotes with backslash-escaping of internal
  # double-quotes may be used to explicitly specify strings. Un-quoted
  # symbols may either begin with a colon, in which case they denote a
  # name, or no colon, in which case they denote a string. Whitespace
  # outside of double-quotes is ignored. Parentheses containing only
  # numbers, periods and plus-signs or minus-signs denote a
  # probability if they directly follow a string or name inside a name
  # definition, or parentheses used to evaluate an expression. The
  # default probability is 1.0 for any unspecified expression. Names
  # may be defined in any order.
  #
  # @example A simple DemiRule name generator
  #     start: :noun(3) | (:adjective + :noun)(+1.3)
  #     noun: swallow(0.1) | heron | grouper(2) | "silly-headed  catfish" | :adjective + " little " + :noun
  #     adjective: green(1.0) | blue(0.7) | mauve(2) | large | "--smaaaaaallll--" | "    itty-bitty    "(0.1)
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
    def load_rules_from_demirule_string(rules)
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

        # To parse a line, we'll first need to tokenize.
        tokens = demirule_tokenize_definition(defn)

        # Then we'll build a tree of operations based on parentheses
        # and order-of-operations of plus versus vertical-bar
        ast = demirule_tokens_to_tree tokens
        @rules[name] = ast
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
      STDERR.puts "Evaluate: #{ast.inspect}"
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

    DOUBLEQUOTE_REGEXP = /("([^\\"]|\\\\|\\")*")/
    def demirule_tokenize_definition(defn)
      # To tokenize, we'll match backslash-escaped double-quoted
      # strings. A token may be a string, an open- or
      # close-parenthesis, a plus, a vertical bar, a colon-prefixed
      # name or non-colon-prefixed string. Whitespace is ignored
      # except inside double quotes.
      tokens = []
      remaining = defn
      match = DOUBLEQUOTE_REGEXP.match(remaining)
      while remaining =~ DOUBLEQUOTE_REGEXP
        pre_text = match.pre_match
        post_text = match.post_match
        tokens.concat(demirule_tokenize_no_strings pre_text)
        tokens.push match[1]

        remaining = post_text
        match = DOUBLEQUOTE_REGEXP.match(remaining)
      end
      tokens.concat(demirule_tokenize_no_strings remaining)
      tokens
    end

    def demirule_tokenize_no_strings(chunk)
      tokens = chunk.split(/(\s+|\||\+|\(|\))/).map(&:strip).select { |s| s != "" }
      tokens
    end

    def demirule_tokens_to_tree(tokens)
      subtrees_and_tokens = demirule_tokens_process_parens tokens
      tagged_tokens = demirule_tokens_tag_untagged subtrees_and_tokens

      # Plus binds tighter than bar, so handle plus first
      subtrees = demirule_tokens_process_bar demirule_tokens_process_plus(tagged_tokens)
      subtrees
    end

    def demirule_tokens_process_parens(tokens)
      unless tokens.include?("(")
        raise ::Demiurge::Errors::DemiRuleFormatError.new("Too many end-parens found", "tokens" => tokens.inspect) if tokens.include?(")")
        return tokens
      end

      first_start = tokens.index("(")

      index = first_start + 1
      tally = 1
      while(index < tokens.length)
        if tokens[index] == "("
          tally += 1
        elsif tokens[index] == ")"
          tally -= 1
        end

        # If this is the corresponding end-paren...
        if tally == 0
          inside_paren_tokens = tokens[(index+1)..(index-1)]
          # Either parens denote a subexpression to evaluate first, or they have a probability. Which?
          inside = inside_paren_tokens.join("")
          if inside =~ /\A(\+|\-)?[0-9]+(\.[0-9]+)\Z/
            # These parens contain a probability
            if index == 1
              # Can't start with a probability
              raise ::Demiurge::Errors::DemiRuleFormatError.new("Can't start an expression with a probability", "tokens" => tokens.inspect, "prob" => prob)
            end
            prob = inside.to_f
            return tokens[0..(index-2)] + [ [:prob, prob ] ] + demirule_tokens_process_parens(tokens[(index+1)..-1])
          else
            # This is a subexpression in parentheses
            subtree = demirule_tokens_to_tree inside_paren_tokens
            return tokens[0..(index-1)] + [:expression, subtree] + demirule_tokens_process_parens(tokens[(index+1)..-1])
          end
        end
        index += 1
      end

      # If we got here, there was no end-paren
      raise ::Demiurge::Errors::DemiRuleFormatError.new("No corresponding end-paren found", "tokens" => tokens.inspect)
    end

    # Parentheses have been handled first, so there will be :expression and :prob elements. The others should be tagged.
    def demirule_tokens_tag_untagged(tokens_and_subtrees)
      out_subtrees = tokens_and_subtrees.map do |elt|
        if elt.is_a?(Array) && [:expression, :prob].include?(elt)
          elt  # No change, keep as it is
        elsif ["+", "|"].include?(elt)
          [ :operator, elt ]
        elsif elt.is_a?(String) && elt[0] != ":"
          [ :string, elt ]
        elsif elt.is_a?(String)
          [ :name, elt ]
        else
          raise ::Demiurge::Errors::DemiRuleFormatError.new("Unexpected token #{elt.inspect}!", "token" => elt.inspect, "tokens" => tokens_and_subtrees.inspect)
        end
      end
      out_subtrees
    end

    def demirule_tokens_process_plus(subtrees)
      if subtrees[0] == [ :operator, "+" ]
        raise ::Demiurge::Errors::DemiRuleFormatError.new("Operator plus can't be first token of an expression", "tokens" => tokens.inspect)
      end
      if subtrees[-1] == [ :operator, "+" ]
        raise ::Demiurge::Errors::DemiRuleFormatError.new("Operator plus can't be last token of an expression", "tokens" => tokens.inspect)
      end
      return subtrees if subtrees.size < 3 || !subtrees.include?([ :operator, "+" ])

    end

    def demirule_tokens_process_binary_operator(tokens, op)
      if tokens[0] == op
        raise ::Demiurge::Errors::DemiRuleFormatError.new("Operator #{op} can't be first token of an expression", "tokens" => tokens.inspect)
      end
      if tokens[-1] == op
        raise ::Demiurge::Errors::DemiRuleFormatError.new("Operator #{op} can't be last token of an expression", "tokens" => tokens.inspect)
      end
      return tokens if tokens.size < 3 || !tokens.include?(op)

      # Divide the tokens up into sublists, divided by this operator
      cur_list = []
      list_of_lists = [ cur_list ]
      tokens.each_with_index do |token, index|
        if token == op
          cur_list = []
          list_of_lists.push(cur_list)
        else
          cur_list.push(token)
        end
      end
      return [ op ] + list_of_lists.flatten(1)
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
