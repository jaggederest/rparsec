require 'src/misc'

class Token
  def_readable :kind, :text, :index
  def length
    @text.length
  end
  def to_s
    "#{@kind}: #{@text}"
  end
end