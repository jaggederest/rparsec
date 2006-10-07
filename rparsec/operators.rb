require 'rparsec/parser'

class String
  def starts_with sub
    return true if sub.nil?
    len = sub.length
    return false if len > length
    for i in (0...len)
      return false if self[i] != sub[i]
    end
    true
  end
end

class Operators
  def initialize(ops)
    @lexers = {}
    sorted = Operators.sort(ops)
    lexers = sorted.map do |op|
      symbol = op.to_sym
      result = nil
      if op.length == 1
        result = Parsers.char(op)
      else
        result = Parsers.str(op)
      end
      result = result.token(symbol)
      @lexers[symbol] = result
    end
    @lexer = Parsers.sum(*lexers)
  end
  def parser(op, &proc)
    Parsers.token(op.to_sym, &proc)
  end
  alias [] parser
  def lexer(op=nil)
    return @lexer if op.nil?
    @lexers[op.to_sym]
  end
  def self.sort(ops)
    #sort the array by longer-string-first.
    ordered = ops.sort {|x, y|y.length <=> x.length}
    suites = []
    # loop from the longer to shorter string
    ordered.each do |s|
      populate_suites(suites, s)
    end
    # suites are populated with bigger suite first
    to_array suites
  end
  private
  def self.populate_suites(suites, s)
    # populate the suites so that bigger suite first
    # this way we can use << operator for non-contained strings.
    
    # we need to start from bigger suite. So loop in reverse order
    for suite in suites
      return if populate_suite(suite, s)
    end
    suites << [s]
  end
  def self.populate_suite(suite, s)
    # loop from the tail of the suite
    for i in (1..suite.length)
      ind = suite.length - i
      cur = suite[ind]
      if cur.starts_with s
        suite.insert(ind+1, s) unless cur == s
        return true
      end
    end
    false
  end
  def self.to_array suites
    result = []
    suites.reverse!.flatten!
  end
end