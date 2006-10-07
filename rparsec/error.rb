require 'misc'
class ParserException < StandardError
  def_readable :index
end
class Failure
  def initialize(ind, input, msg=nil)
    @index, @input, @msg = ind, input, msg
  end
  attr_reader :index, :input
  def msg
    return @msg.to_s
  end
  Precedence = 100
end

class Expected < Failure
  Precedence = 100
end