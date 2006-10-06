require 'runit/testcase'
require 'src/id_monad'
require 'src/monad'

class Idm
  include Monad
  MyMonad = IdMonad.new
  def initialize(v)
    initMonad(MyMonad, v);
  end
  def to_s
    @obj.to_s
  end
end

class SimpleMonadTest < RUNIT::TestCase
  def test1
    assert 20, Idm.new(10).map{|i|i*2}
    assert 10, Idm.new(10).plus(Idm.new(20))
  end
end

x , y = 1, 2

def change(x,y)
  x, y = 3,4
end
change(x,y)
puts x, y
