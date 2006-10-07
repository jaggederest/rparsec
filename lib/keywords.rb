require 'parsers'

class Keywords
  extend Parsers
  private_class_method :new
  attr_reader :keyword_symbol, :lexer
  def case_sensitive?
    @case_sensitive
  end
  def self.case_sensitive(words, default_lexer=word.token(:word), keyword_symbol=:keyword, &block)
    new(words, true, default_lexer, keyword_symbol, block)
  end
  def self.case_insensitive(words, default_lexer=word.token(:word), keyword_symbol=:keyword, &block)
    new(words, false, default_lexer, keyword_symbol, block)
  end
  # scanner has to return a string
  def initialize(words, case_sensitive, default_lexer, keyword_symbol, block)
    @default_lexer, @case_sensitive, @keyword_symbol = default_lexer, case_sensitive, keyword_symbol
    # this guarantees that we have copy of the words array and all the word strings.
    words = copy_words(words, case_sensitive)
    @name_map = {}
    @symbol_map = {}
    word_map = {}
    words.each do |w|
      symbol = :"#{keyword_symbol}:#{w}"
      word_map[w] = symbol
      parser = Parsers.token(symbol, &block)
      @symbol_map[:"#{w}"] = parser
      @name_map[w] = parser
    end
    @lexer = make_lexer(default_lexer, word_map)
  end
  def parser(key)
    result = nil
    if key.kind_of? String
      name = canonical_name(key)
      result = @name_map[name]
    else
      result = @symbol_map[key]
    end
    raise ArgumentError, "parser not found for #{key}" if result.nil?
    result
  end
  alias [] parser
  private
  def make_lexer(default_lexer, word_map)
    default_lexer.map do |tok|
      text,ind = tok.text, tok.index
      key = canonical_name(text)
      my_symbol = word_map[key]
      case when my_symbol.nil? : tok
        else Token.new(my_symbol, text, ind) end
    end
  end
  def canonical_name(name)
    case when @case_sensitive: name else name.downcase end
  end
  def copy_words(words, case_sensitive)
    words.map do |w|
      case when case_sensitive: w.dup else w.downcase end
    end
  end
end