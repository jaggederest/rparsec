require 'src/monad'
require 'src/misc'
require 'src/error'
require 'src/context'
require 'src/locator'
require 'src/token'
require 'strscan'
require 'src/functors'
class ParserMonad
  def fail msg
    FailureParser.new(msg)
  end
  def value v
    return Nil if v.nil?
    ValueParser.new(v);
  end
  def bind(v, &proc)
    BoundParser.new(v, proc);
  end
  def mplus(p1, p2)
    PlusParser.new([p1,p2]);
  end
end

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
end


class FailureParser < Parser
  init :msg
  def _parse ctxt
    return ctxt.failure(@msg)
  end
end

class ValueParser < Parser
  init :value
  def _parse ctxt
    ctxt.retn @value
  end
end

class LazyParser < Parser
  init :block
  def _parse ctxt
    @block.call._parse ctxt
  end
end

def add_error(err, e)
  return e if err.nil?
  return err if e.nil?
  cmp = compare_error(err, e)
  return err if cmp > 0
  return e if cmp < 0
  merge_error(err, e)
end
def get_first_element(err)
  while err.kind_of?(Array)
    err = err[0]
  end
  err
end

def compare_error(e1, e2)
  e1, e2 = get_first_element(e1), get_first_element(e2)
  return -1 if e1.index < e2.index
  return 1 if e1.index > e2.index
  0
end

def merge_error(e1, e2)
  return e1 << e2 if e1.kind_of?(Array)
  [e1,e2]
end
class ThrowParser < Parser
  init :symbol
  def _parse ctxt
    throw @symbol
  end
end
class CatchParser < Parser
  init :symbol, :parser
  def _parse ctxt
    interrupted = true
    ok = false
    catch @symbol do
      ok = @parser._parse(ctxt)
      interrupted = false
    end
    return ctxt.retn(@symbol) if interrupted
    ok
  end
end

class PeekParser < Parser
  init :parser
  def _parse ctxt
    ind = ctxt.index
    return false unless @parser._parse ctxt
    ctxt.index = ind
    return true
  end
  def peek
    self
  end
end

class AtomParser < Parser
  init :parser
  def _parse ctxt
    ind = ctxt.index
    return true if @parser._parse ctxt
    ctxt.index = ind
    return false
  end
  def atomize
    self
  end
end

class LookAheadSensitiveParser < Parser
  def initialize(la=1)
    super()
    @lookahead = la
  end
  def visible(ctxt, n)
    ctxt.index - n < @lookahead
  end
  def lookahead(n)
    raise ArgumentError, "lookahead number #{n} should be positive" unless n>0
    return self if n == @lookahead
    withLookahead(n)
  end
  def not(msg="#{self} unexpected")
    NotParser.new(self, msg, @lookahead)
  end
end


class NotParser < LookAheadSensitiveParser
  def initialize(parser, msg, la=1)
    super(la)
    @parser, @msg, @name = parser, msg, "~#{parser.name}"
  end
  def _parse ctxt
    ind = ctxt.index
    if @parser._parse ctxt
      ctxt.index = ind
      return ctxt.expecting(@msg)
    end
    return ctxt.retn(nil) if visible(ctxt, ind)
    return false
  end
  def withLookahead(n)
    NotParser.new(@parser, @msg, n)
  end
  def not()
    @parser
  end
end

class ExpectParser < Parser
  def initialize(parser, msg)
    super()
    @parser, @msg, @name = parser, msg, msg
  end
  def _parse ctxt
    ind = ctxt.index
    return true if @parser._parse ctxt
    return false unless ind == ctxt.index
    ctxt.expecting(@msg)
  end
end

class PlusParser < LookAheadSensitiveParser
  def initialize(alts, la=1)
    super(la)
    @alts = alts
  end
  def _parse ctxt
    ind = ctxt.index
    result = ctxt.result
    err = ctxt.error
    for p in @alts
      ctxt.reset_error
      ctxt.index = ind
      ctxt.result = result
      return true if p._parse(ctxt)
      return false unless visible(ctxt, ind)
      err = add_error(err, ctxt.error)
    end
    ctxt.error = err
    return false
  end
  def withLookahead(n)
    PlusParser.new(@alts, n)
  end
  def plus other
    PlusParser.new(@alts.dup << other, @lookahead).setName(name)
  end
  def_sig :plus, Parser
end


class BestParser < Parser
  init :alts, :longer
  def _parse ctxt
    best_result, best_ind = nil, -1
    err_ind = -1
    ind = ctxt.index
    result = ctxt.result
    err = ctxt.error
    for p in @alts
      ctxt.reset_error
      ctxt.index = ind
      ctxt.result = result
      if p._parse(ctxt)
        err = nil
        now_ind = ctxt.index
        if best_ind==-1 || now_ind != best_ind && @longer == (now_ind>best_ind)
          best_result, best_ind = ctxt.result, now_ind
        end
      elsif best_ind < 0 # no good match found yet.
        if ctxt.index > err_ind
          err_ind = ctxt.index
        end
        err = add_error(err, ctxt.error)
      end
    end
    if best_ind >= 0
      ctxt.index = best_ind
      return ctxt.retn(best_result)
    else
      ctxt.error = err
      ctxt.index = err_ind
      return false
    end
  end
end

class BoundParser < LookAheadSensitiveParser
  init :parser, :proc
  def _parse ctxt
    return false unless @parser._parse(ctxt)
    @proc.call(ctxt.result)._parse ctxt
  end
end

class SequenceParser < Parser
  init :parsers, :proc
  def _parse ctxt
    if @proc.nil?
      for p in @parsers
        return false unless p._parse(ctxt)
      end
    else
      results = []
      for p in @parsers
        return false unless p._parse(ctxt)
        results << ctxt.result
      end
      ctxt.retn(@proc.call(*results))
    end
    return true
  end
  def seq(other, &block)
    # TypeChecker.check_arg_type Parser, other, :seq
    SequenceParser.new(@parsers.dup << other, &block)
  end
  def_sig :seq, Parser
end

class FollowedParser < Parser
  init :p1, :p2
  def _parse ctxt
    return false unless @p1._parse ctxt
    result = ctxt.result
    return false unless @p2._parse ctxt
    ctxt.retn(result)
  end
end

class SatisfiesParser < Parser
  init :pred, :expected
  def _parse ctxt
    elem = nil
    if ctxt.eof || !@pred.call(elem=ctxt.current)
      return ctxt.expecting(@expected)
    end
    ctxt.next
    ctxt.retn elem
  end
end
class AnyParser < Parser
  def _parse ctxt
    return ctxt.expecting if ctxt.eof
    result = ctxt.current
    ctxt.next
    ctxt.retn result
  end
end

class EofParser < Parser
  init :msg
  def _parse ctxt
    return true if ctxt.eof
    return ctxt.expecting(@msg)
  end
end
class RegexpParser < Parser
  init :ptn, :msg
  def _parse ctxt
    scanner = ctxt.scanner
    result = scanner.check @ptn
    if result.nil?
      ctxt.expecting(@msg)
    else
      ctxt.advance(scanner.matched_size)
      ctxt.retn(result)
    end
  end
end
class AreParser < Parser
  init :vals, :msg
  def _parse ctxt
    if @vals.length > ctxt.available
      return ctxt.expecting(@msg)
    end
    cur = 0
    for cur in (0...@vals.length)
      if @vals[cur] != ctxt.peek(cur)
        return ctxt.expecting(@msg)
      end
    end
    ctxt.advance(@vals.length)
    ctxt.retn @vals
  end
end

def downcase c
  case when c >= ?A && c <=?Z : c + (?a - ?A) else c end
end

class StringCaseInsensitiveParser < Parser
  init :str, :msg
  def _parse ctxt
    if @str.length > ctxt.available
      return ctxt.expecting(@msg)
    end
    cur = 0
    for cur in (0...@str.length)
      if downcase(@str[cur]) != downcase(ctxt.peek(cur))
        return ctxt.expecting(@msg)
      end
    end
    result = ctxt.src[ctxt.index, @str.length]
    ctxt.advance(@str.length)
    ctxt.retn result
  end
end
class FragmentParser < Parser
  init :parser
  def _parse ctxt
    ind = ctxt.index
    return false unless @parser._parse ctxt
    ctxt.retn(ctxt.src[ind, ctxt.index-ind])
  end
end

class TokenParser < Parser
  init :symbol, :parser
  def _parse ctxt
    ind = ctxt.index
    return false unless @parser._parse ctxt
    raw = ctxt.result
    raw = ctxt.src[ind, ctxt.index-ind] unless raw.kind_of? String
    ctxt.retn(Token.new(@symbol, raw, ind))
  end
end

class NestedParser < Parser
  init :parser1, :parser2
  def _parse ctxt
    ind = ctxt.index
    return false unless @parser1._parse ctxt
    _run_nested(ind, ctxt, ctxt.result, @parser2)
  end
  private
  def _run_nested(start, ctxt, src, parser)
    ctxt.error = nil
    if src.kind_of? String
      new_ctxt = ParseContext.new(src)
      return true if _run_parser parser, ctxt, new_ctxt
      ctxt.index = start + new_ctxt.index
    elsif src.kind_of? Array
      new_ctxt = ParseContext.new(src)
      return true if _run_parser parser, ctxt, new_ctxt
      ctxt.index = start + _get_index(new_ctxt) unless new_ctxt.eof
    else
      new_ctxt = ParseContext.new([src])
      return true if _run_parser parser, ctxt, new_ctxt
      ctxt.index = ind unless new_ctxt.eof
    end
    false
  end
  def _get_index ctxt
    cur = ctxt.current
    return cur.index if cur.respond_to? :index
    ctxt.index
  end
  def _run_parser parser, old_ctxt, new_ctxt
    if parser._parse new_ctxt
      old_ctxt.result = new_ctxt.result
      true
    else
      old_ctxt.error = new_ctxt.error
      false
    end
  end
end


class Repeat_Parser < Parser
  init :parser, :times
  def _parse ctxt
    for i in (0...@times)
      return false unless @parser._parse ctxt
    end
    return true
  end
end

class RepeatParser < Parser
  init :parser, :times
  def _parse ctxt
    result = []
    for i in (0...@times)
      return false unless @parser._parse ctxt
      result << ctxt.result
    end
    return ctxt.retn(result)
  end
end

class Many_Parser < Parser
  init :parser, :least
  def _parse ctxt
    for i in (0...@least)
      return false unless @parser._parse ctxt
    end
    while(true)
      ind = ctxt.index
      if @parser._parse ctxt
        return true if ind==ctxt.index # infinite loop
        next
      end
      return ind==ctxt.index
    end
  end
end


class ManyParser < Parser
  init :parser, :least
  def _parse ctxt
    result = []
    for i in (0...@least)
      return false unless @parser._parse ctxt
      result << ctxt.result
    end
    while(true)
      ind = ctxt.index
      if @parser._parse ctxt
        result << ctxt.result
        return ctxt.retn(result) if ind==ctxt.index # infinite loop
        next
      end
      if ind==ctxt.index
        return ctxt.retn(result)
      else
        return false
      end
    end
  end
end

class Some_Parser < Parser
  init :parser, :least, :max
  def _parse ctxt
    for i in (0...@least)
      return false unless @parser._parse ctxt
    end
    for i in (@least...@max)
      ind = ctxt.index
      if @parser._parse ctxt
        return true if ind==ctxt.index # infinite loop
        next
      end
      return ind==ctxt.index
    end
    return true
  end
end

class SomeParser < Parser
  init :parser, :least, :max
  def _parse ctxt
    result = []
    for i in (0...@least)
      return false unless @parser._parse ctxt
      result << ctxt.result
    end
    for i in (@least...@max)
      ind = ctxt.index
      if @parser._parse ctxt
        result << ctxt.result
        return ctxt.retn(result) if ind==ctxt.index # infinite loop
        next
      end
      if ind==ctxt.index
        return ctxt.retn(result)
      else
        return false
      end
    end
    return ctxt.retn(result)
  end
end

class OneParser < Parser
  def _parse ctxt
    true
  end
end

class ZeroParser < Parser
  def _parse ctxt
    return ctxt.failure
  end
end

class GetIndexParser < Parser
  def _parse ctxt
    ctxt.retn(ctxt.index)
  end
end

Nil = ValueParser.new(nil)
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
