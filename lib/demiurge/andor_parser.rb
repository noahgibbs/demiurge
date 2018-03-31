require "parslet"
module Demiurge
  # This parser syntax, used for name-generator files, gets called
  # "Andor" for its simple "and/or" formulation of name rules.
  class AndorDefnParser < Parslet::Parser
    root :bar_expr

    rule(:bar_expr) {
      space? >> plus_expr.as(:left) >> (bar.as(:bar) >> plus_expr.as(:right)).repeat(1) |
      space? >> plus_expr |
      space? >> str('(') >> space? >> bar_expr >> space? >> str(')')
    }

    rule(:plus_expr) {
      str_or_name.as(:left) >> (plus.as(:plus) >> str_or_name.as(:right)).repeat(1) |
      str_or_name |
      str('(') >> space? >> bar_expr >> space? >> str(')')
    }

    rule(:space)  { match('\s').repeat(1) }
    rule(:space?) { space.maybe }
    rule(:name) { str(':') >> match('[-_$a-zA-Z0-9]').repeat(1).as(:name) >> space? }
    rule(:str_const) { match('[-_$a-zA-Z0-9]').repeat(1).as(:str_const) >> space? }
    rule(:str_or_name) { quoted_string | str_const | name }
    rule(:plus) { str('+').as(:plus) >> space? }
    rule(:bar) { str('|').as(:bar) >> space? }
    rule(:prob) { str('(') >> space? >> (match('[0-9]').repeat(1) >> (str('.') >> match('[0-9]').repeat(1)).maybe).as(:prob) >> space? >> str(')') >> space? }

    rule(:quote) { str('"') }
    rule(:nonquote) { str('"').absnt? >> any }
    rule(:string_escape)     { str('\\') >> any.as(:esc) }
    rule(:quoted_string) { quote >> (
        string_escape |
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
