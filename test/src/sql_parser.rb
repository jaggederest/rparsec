require 'import'
import :parsers, :keywords, :operators, :functors, :expressions

module SqlParser
  include Functors
  include Parsers
  MyKeywords = Keywords.case_insensitive(%w{
    select from where group by having order desc asc
    inner left right full outer inner join on cross
    union all distinct as
    case when else end and or not true false
  })
  MyOperators = Operators.new(%w{+ - * / % == > < >= <= <> != : ( ) . ,})
  MyLexer = Parsers.integer.token(:int) | MyKeywords.lexer | MyOperators.lexer
  MyLexeme = MyLexer.lexeme(Parsers.whitespaces | Parsers.comment_line('#')) << Parsers.eof
  def keyword
    MyKeywords
  end
  def operator
    MyOperators
  end
  def word(&block)
    if block.nil?
      token(:word, &Id)
    else
      token(:word, &block)
    end
  end 
  def calculate_simple_cases(val, cases, default)
    SimpleCaseExpr.new(val, cases, default)
  end
  def calculate_full_cases(cases, default)
    CaseExpr.new(cases, default)
  end
  def make_bool_expression expr
    compare = operator['>'] >> Gt | operator['<'] >> Lt | operator['>='] >> Ge | operator['<='] >> Le |
      operator['=='] >> Eq | operator['!='] >> Ne | operator['<>'] >> Ne
    comparison = sequence(expr, compare, expr) {|e1,f,e2|f.call(e1,e2)}
    bool = nil
    lazy_bool = lazy{bool}
    bool_term = keyword[:true] >> true | keyword[:false] >> false |
      comparison | operator['('] >> lazy_bool << operator[')']
    bool_table = OperatorTable.new.
      infixl(keyword[:or] >> Or, 20).
      infixl(keyword[:and] >> And, 30).
      infixl(keyword[:not] >> Not, 30)
    bool = Expressions.build(bool_term, bool_table)
  end
  def make_expression bool
    expr = nil
    lazy_expr = lazy{expr}
    simple_case = sequence(keyword[:when], lazy_expr, operator[':'], lazy_expr) do |w,cond,t,val|
      [cond, val]
    end
    full_case = sequence(keyword[:when], bool, operator[':'], lazy_expr) do |w,cond,t,val|
      [cond, val]
    end
    default_case = (keyword[:else] >> lazy_expr).optional
    simple_when_then = sequence(lazy_expr, simple_case.many, default_case, 
      keyword[:end]) do |val, cases, default|
      calculate_simple_cases(val, cases, default)
    end
    full_when_then = sequence(full_case.many, default_case, keyword[:end]) do |cases, default|
      calculate_full_cases(cases, default)
    end
    case_expr = keyword[:case] >> (simple_when_then | full_when_then)
    wildcard = operator[:*] >> WildcardExpr::Instance
    lit = token(:int) {|l|LiteralExpr.new l}
    atom = lit | wildcard |
      sequence(word, operator['.'], word|wildcard) {|owner, _, col| QualifiedColumnExpr.new owner, col} |
      word {|w|WordExpr.new w}
    term = atom | (operator['('] >> lazy_expr << operator[')']) | case_expr
    table = OperatorTable.new.
      infixl(operator['+'] >> Plus, 20).
      infixl(operator['-'] >> Minus, 20).
      infixl(operator['*'] >> Mul, 30).
      infixl(operator['/'] >> Div, 30).
      infixl(operator['%'] >> Mod, 30).
      prefix(operator['-'] >> Neg, 50)
    expr = Expressions.build(term, table)
  end
  def make_relation expr
    exprs = expr.delimited1(operator[','])
    relation = nil
    lazy_relation = lazy{relation}
    term_relation = word {|w|TableRelation.new w} | operator['('] >> lazy_relation << operator[')']
    sub_relation = sequence(term_relation, (keyword[:as].optional >> word).optional) do |rel, name|
      case when name.nil?: rel else AliasRelation.new(rel, name) end
    end
    relation = sequence(keyword[:select], exprs, keyword[:from], sub_relation) do |_, projected, _, from|
      SelectRelation.new(projected, from)
    end
  end
  def expression
    expr = nil
    expr = make_expression(make_bool_expression(lazy{expr}))
  end

  def relation
    make_relation(expression)
  end

  def make parser
    MyLexeme.nested(parser << eof)
  end
end