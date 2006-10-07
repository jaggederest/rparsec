require 'import'
require 'parsers'
require 'parser_test'
require 'operators'
class OperatorTestCase < ParserTestCase
  Ops = Operators.new(%w{++ + - -- * / ~})
  def verifyToken(src, op)
    verifyParser(src, op, Ops.parser(op){|x|x})
  end
  def verifyParser(src, expected, parser)
    assertParser(src, expected, Ops.lexer.lexeme.nested(parser))
  end
  def testAll
    verifyToken('++ -', '++')
    verifyParser('++ + -- ++ - +', '-', 
      (Ops['++']|Ops['--']|Ops['+']).many_ >> Ops.parser('-'){|x|x})
  end
  def testSort
    assert_equal(%w{+++ ++- ++ + --- -- -}, Operators.sort(%w{++ - + -- +++ ++- ---}))
  end
end