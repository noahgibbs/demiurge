require "parslet"
module Demiurge
  # This parser syntax, used for name-generator files, gets called
  # "Andor" for its simple "and/or" formulation of name rules.  This
  # parser is used only for definitions - a much simpler parser based
  # on "split" and Ruby code cuts apart the simple outer structure.
  #
  # @since 0.4.0
  class AndorDefnParser < Parslet::Parser
    root :bar_expr

    # The way we do operator precedence is to have "plus expressions"
    # and "bar expressions", plus "value expressions". A plus_expr
    # binds "tighter" than a bar expr, which effectively handles
    # plusses before bars, and the same for value-expressions.
    # Parentheses "bind" a sub-expression into a highest-precedence
    # "value" expression like a constant.

    rule(:bar_expr) {
      space? >> plus_expr.as(:left) >> space? >> prob?.as(:left_prob) >> space? >> (bar.as(:bar) >> space? >> plus_expr.as(:right) >> space? >> prob?.as(:right_prob) >> space?).repeat(1) >> space? |
      plus_expr
    }

    rule(:plus_expr) {
      space? >> value_expr.as(:left) >> space? >> (plus.as(:plus) >> space? >> value_expr.as(:right)).repeat(1) >> space? |
      space? >> str_or_name >> space? |
      value_expr
    }

    rule(:value_expr) {
      space? >> quoted_string >> space? |
      space? >> str_const >> space? |
      space? >> name >> space? |
      space? >> str('(') >> space? >> bar_expr >> space? >> str(')') >> space?
    }

    rule(:space)  { match('\s').repeat(1) }
    rule(:space?) { space.maybe }
    rule(:name) { str(':') >> match('[-_$a-zA-Z0-9]').repeat(1).as(:name) >> space? }
    rule(:str_const) { match('[-_$a-zA-Z0-9]').repeat(1).as(:str_const) >> space? }
    rule(:str_or_name) { quoted_string | str_const | name }
    rule(:plus) { str('+').as(:plus) >> space? }
    rule(:bar) { str('|').as(:bar) >> space? }
    rule(:prob) { str('(') >> space? >> (match('[0-9]').repeat(1) >> (str('.') >> match('[0-9]').repeat(1)).maybe).as(:prob) >> space? >> str(')') >> space? }
    rule(:prob?) { prob.maybe }

    rule(:quote) { str('"') }
    rule(:nonquote) { str('"').absnt? >> any }
    rule(:escaped_quote) { str('\\"') }
    rule(:quoted_string) { quote >> (
        escaped_quote.as(:char) |
        nonquote.as(:char)
        ).repeat(1).as(:str_val) >> quote >> space? }

  end
end

#def parse(str)
#    mini = DemiRuleDefn.new
#
#    mini.parse(str)
#  rescue Parslet::ParseFailed => failure
#    puts failure.parse_failure_cause.ascii_tree
#end
