%w{
monad misc error context locator token functors parser_monad
}.each {|lib| require "rparsec/#{lib}"}
require 'strscan'


#
# Represents a parser that parses a certain grammar rule.
#
class Parser
  include Functors
  include Monad
  extend Signature
  MyMonad = ParserMonad.new
  attr_accessor :name
  private
  def initialize
    initMonad(MyMonad, self)
  end
  def self.init(*vars)
    parser_checker = {}
    vars.each_with_index do |var, i|
      name = var.to_s
      parser_checker[i] = var if name.include?('parser') && !name.include?('parsers')
    end
    define_method(:initialize) do |*params|
      super()
      vars.each_with_index do |var, i|
        param = params[i]
        if parser_checker.include? i
          TypeChecker.check_arg_type Parser, param, self, i
        end
        instance_variable_set("@"+var.to_s, param)
      end
    end
  end
  def _display_current_input(input, code, index)
    return 'EOF' if input.nil?
    c = input
    case c when Fixnum: "'"<<c<<"'" when Token: c.text else c.to_s end
  end
  def _add_encountered_error(msg, encountered)
    result = msg.dup
    result << ', ' unless msg.strip.length == 0 || msg =~ /.*(\.|,)\s*$/
    "#{result}#{encountered}"
  end
  def _add_location_to_error(locator, ctxt, msg, code)
    line, col = locator.locate(ctxt.index)
    msg << " at line #{line}, col #{col}."
  end
  public
  #
  # parses a string
  #
  def parse(src)
    ctxt = ParseContext.new(src)
    return ctxt.result if _parse ctxt
    ctxt.prepare_error
    locator = CodeLocator.new(src)
    raise ParserException.new(ctxt.index), 
      _add_location_to_error(locator, ctxt, 
        _add_encountered_error(ctxt.to_msg,
           _display_current_input(ctxt.error_input, src, ctxt.index)), src)
  end
  def setName(nm)
    @name = nm
    self
  end
  def atomize
    AtomParser.new(self).setName(@name)
  end
  def peek
    PeekParser.new(self).setName(@name)
  end
  def not(msg="#{self} unexpected")
    NotParser.new(self, msg)
  end
  def lookahead n
    self
  end
  def expect msg
    ExpectParser.new(self, msg)
  end
  def followed(other)
    FollowedParser.new(self, other)
  end
  def_sig :followed, Parser
  def repeat_(min, max=min)
    return Parsers.failure("min=#{min}, max=#{max}") if min > max
    if(min==max)
      return Parsers.one if max <= 0
      return self if max == 1
      Repeat_Parser.new(self, max)
    else
      Some_Parser.new(self, min, max)
    end
  end
  def repeat(min, max=min)
    return Parsers.failure("min=#{min}, max=#{max}") if min > max
    if(min==max)
      RepeatParser.new(self, max)
    else
      SomeParser.new(self, min, max)
    end
  end
  def many_(least=0)
    Many_Parser.new(self, least)
  end
  def many(least=0)
    ManyParser.new(self, least)
  end
  def some_(max)
    repeat_(0, max)
  end
  def some(max)
    repeat(0, max)
  end
  def separated1 delim
    rest = delim >> self
    self.bind do |v0|
      result = [v0]
      (rest.map {|v| result << v}).many_ >> value(result)
    end
  end
  def separated delim
    separated1(delim) | value([])
  end
  def delimited1 delim
    rest = delim >> (self | Parsers.throwp(:__end_delimiter__))
    self.bind do |v0|
      result = [v0]
      (rest.map {|v| result << v}).many_.catchp(:__end_delimiter__) >> value(result)
    end
  end
  def delimited delim
    delimited1(delim) | value([])
  end
  def to_s
    return name unless name.nil?
    self.class.to_s
  end
  def | other
    plus(autobox_parser(other))
  end
  def optional(default=nil)
    plus(value(default))
  end
  def catchp(symbol)
    Parsers.catchp(symbol, self)
  end
  def fragment
    FragmentParser.new(self)
  end
  def nested(parser)
    NestedParser.new(self, parser)
  end
  def lexeme(delim = Parsers.whitespaces)
    delim = delim.many_
    delim >> self.delimited(delim)
  end
  def prefix(op)
    Parsers.sequence(op.many, self) do |funcs, v|
      funcs.reverse_each {|f|v=f.call(v)}
      v
    end
  end
  def postfix(op)
    Parsers.sequence(self, op.many) do |v, funcs|
      funcs.each{|f|v=f.call(v)}
      v
    end
  end
  def infixn(op)
    bind do |v1|
      bin = Parsers.sequence(op, self) do |f, v2|
        f.call(v1,v2)
      end
      bin | value(v1)
    end
  end
  def infixl(op)
    Parsers.sequence(self, _infix_rest(op, self).many) do |v, rests|
      rests.each do |r|
        f, v1 = *r
        v = f.call(v,v1)
      end
      v
    end
  end
  def infixr(op)
    Parsers.sequence(self, _infix_rest(op, self).many) do |v, rests|
      if rests.empty?
        v
      else
        f, seed = *rests.last
        for i in (0...rests.length-1)
          cur = rests.length-2-i
          f1, v1 = *rests[cur]
          seed = f.call(v1, seed)
          f = f1
        end
        f.call(v, seed)
      end
    end
  end
  def token(kind)
    TokenParser.new(kind, self)
  end
  def seq(other, &block)
    # TypeChecker.check_arg_type Parser, other, :seq
    Parsers.sequence(self, other, &block)
  end
  def_sig :seq, Parser
  def >> (other)
    seq(autobox_parser(other))
  end
  private
  def autobox_parser(val)
    return Parsers.value(val) unless val.kind_of? Parser
    val
  end
  def _infix_rest(operator, operand)
    Parsers.sequence(operator, operand, &Idn)
  end
  public
  alias ~ not
  alias << followed
  alias * repeat_
  def_sig :plus, Parser
  private
  def _parse(ctxt)
    false
  end
end

module Parsers
  extend Signature
  def failure msg
    FailureParser.new(msg)
  end
  def value v
    ValueParser.new(v)
  end
  def sum(*alts)
    # TypeChecker.check_vararg_type Parser, alts, :sum
    PlusParser.new(alts)
  end
  def_sig :sum, [Parser]
  def satisfies(expected, &proc)
    SatisfiesParser.new(proc, expected)
  end
  def is(v, expected="#{v} expected")
    satisfies(expected) {|c|c==v}
  end
  def isnt(v, expected="#{v} unexpected")
    satisfies(expected) {|c|c!=v}
  end
  def among(*vals)
    expected="one of [#{vals.join(', ')}] expected"
    vals = as_list vals
    satisfies(expected) {|c|vals.include? c}
  end
  def not_among(*vals)
    expected = "one of [#{vals.join(', ')}] unexpected"
    vals = as_list vals
    satisfies(expected) {|c|!vals.include? c}
  end
  def char(c)
    if c.kind_of? Fixnum
      nm = c.chr
      is(c, "'#{nm}' expected").setName(nm)
    else
      is(c[0], "'#{c}' expected").setName(c)
    end
  end
  def not_char(c)
    if c.kind_of? Fixnum
      nm = c.chr
      isnt(c, "'#{nm}' unexpected").setName("~#{nm}")
    else
      isnt(c[0], "'#{c}' unexpected").setName("~#{c}")
    end
  end
  
  def eof(expected="EOF expected")
    EofParser.new(expected).setName('EOF')
  end
  def are(vals, expected="#{vals} expected")
    AreParser.new(vals, expected)
  end
  def arent(vals, expected="#{vals} unexpected")
    are(vals, '').not(expected) >> any
  end
  def string(str)
    are(str, "\"#{str}\" expected").setName(str)
  end
  def not_string(str, msg="\"#{str}\" unexpected")
    string(str).not(msg) >> any
  end
  def str(str)
    string(str)
  end
  def sequence(*parsers, &proc)
    # TypeChecker.check_vararg_type Parser, parsers, :sequence
    SequenceParser.new(parsers, proc)
  end
  def_sig :sequence, [Parser]
  def index
    GetIndexParser.new.setName("index")
  end
  def longest(*parsers)
    # TypeChecker.check_vararg_type Parser, parsers, :longest
    BestParser.new(parsers, true)
  end
  def_sig :longest, [Parser]
  def shortest(*parsers)
    # TypeChecker.check_vararg_type Parser, parsers, :shortest
    BestParser.new(parsers, false)
  end
  def_sig :shortest, [Parser]
  def shorter(*parsers)
    shortest(*parsers)
  end
  def longer(*parsers)
    longest(*parsers)
  end
  def any
    AnyParser.new
  end
  def zero
    ZeroParser.new
  end
  def one
    OneParser.new
  end
  def range(from, to, msg="#{as_char from}..#{as_char to} expected")
    from, to = as_num(from), as_num(to)
    satisfies(msg) {|c| c <= to && c >= from}
  end
  def throwp(symbol)
    ThrowParser.new(symbol)
  end
  def catchp(symbol, parser)
    CatchParser.new(symbol, parser)
  end
  def regexp(ptn, expected="/#{ptn.to_s}/ expected")
    RegexpParser.new(as_regexp(ptn), expected).setName(expected)
  end
  def word(expected='word expected')
    regexp(/[a-zA-Z_]\w*/, expected)
  end
  def integer(expected='integer expected')
    regexp(/\d+(?!\w)/, expected)
  end
  def number(expected='number expected')
    regexp(/\d+(\.\d+)?/, expected)
  end
  def string_nocase(str, expected="'#{str}' expected")
    StringCaseInsensitiveParser.new(str, expected).setName(str)
  end
  def token(kind, expected="#{kind} expected", &proc)
    recognizer = satisfies(expected) do |tok|
      tok.respond_to? :kind, :text and kind == tok.kind
    end
    recognizer = recognizer.map{|tok|proc.call(tok.text)} unless proc.nil?
    recognizer
  end
  def whitespace(expected="whitespace expected")
    satisfies(expected) {|c| Whitespaces.include? c}
  end
  def whitespaces(expected="whitespace(s) expected")
    whitespace(expected).many_(1)
  end
  def comment_line start
    string(start) >> not_char(?\n).many_ >> char(?\n).optional >> value(nil)
  end
  def comment_block open, close
    string(open) >> not_string(close).many_ >> string(close) >> value(nil)
  end
  def lazy(&block)
    LazyParser.new(block)
  end
  Whitespaces = " \t\r\n\t"
  private
  def as_regexp ptn
    case ptn when String: Regexp.new(ptn) else ptn end
  end
  def as_char c
    case c when String: c else c.chr end
  end
  def as_num c
    case c when String: c[0] else c end
  end
  def as_list vals
    return vals unless vals.length==1
    val = vals[0]
    return vals unless val.kind_of? String
    val
  end
  extend self
end

