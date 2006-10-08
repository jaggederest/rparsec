require 'rparsec/misc'

#
# This class represents a token during lexical analysis.
#
class Token
  def_readable :kind, :text, :index
  #
  # The length of the token.
  #
  def length
    @text.length
  end
  #
  # String representation of the token.
  # 
  def to_s
    "#{@kind}: #{@text}"
  end
end