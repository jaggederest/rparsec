require 'parser_test'
require 'sql'
require 'sql_parser'
class SqlTestCase < ParserTestCase
  include SqlParser
  def verify_sql(code, expected, parser)
    assert_equal(expected, make(parser).parse(code).to_s)
  end
  def testSimpleExpression
    verify_sql('1+2+3', '((1 + 2) + 3)', expression)
  end
  def testExpressionWithBool
    verify_sql('1+Case 2 when 1: x else dbo.y end', '(1 + case 2 when 1: x else dbo.y end)', expression)
  end
  def testExpressionWithWildcard
    verify_sql('a.*', 'a.*', expression)
  end
  def testSimpleRelation
    verify_sql('select * from table1', 'select * from table1', relation)
  end
  def testSubRelation
    verify_sql('select * from (select a, b, c.* from c)', 'select * from (select a, b, c.* from c)', relation)
  end
  def testSimpleRelationWithAlias
    verify_sql('select x.* from table1 x', 'select x.* from table1 AS x', relation)
  end
  def testSubRelationWithAlias
    verify_sql('select * from (select a, b, c.* from c) x', 'select * from (select a, b, c.* from c) AS x', relation)
  end
  def testRelationWithWhere
    verify_sql('select * from table where x=1', 'select * from table where x = 1', relation)
  end
end