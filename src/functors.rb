module Functors
  Id = proc {|x|x}
  Idn = proc {|*x|x}
  Neg = proc {|x|-x}
  Inc = proc {|x|x+1}
  Dec = proc {|x|x-1}
  Plus = proc {|x,y|x+y}
  Minus = proc {|x,y|x-y}
  Mul = proc {|x,y|x*y}
  Div = proc {|x,y|x/y}
  Mod = proc {|x,y|x%y}
  Not = proc {|x,y|!x}
  And = proc {|x,y|x&&y}
  Or = proc {|x,y|x||y}
  Xor = proc {|x,y|x^y}
  BitAnd = proc {|x,y|x&y}
  Union = proc {|x,y|x|y}
  Match = proc {|x,y|x=~y}
  Eq = proc {|x,y|x==y}
  Ne = proc {|x,y|x!=y}
  Lt = proc {|x,y|x<y}
  Gt = proc {|x,y|x>y}
  Le = proc {|x,y|x<=y}
  Ge = proc {|x,y|x>=y}
  Compare = proc {|x,y|x<=>y}
  Call = proc {|x,y|x.call(y)}
  Feed = proc {|x,y|y.call(x)}
  Fst = proc {|x,null|x}
  Snd = proc {|null, x|x}
  At = proc {|x,y|x[y]}
  To_a = proc {|x|x.to_a}
  To_s = proc {|x|x.to_s}
  To_i = proc {|x|x.to_i}
  To_sym = proc {|x|x.to_sym}
  To_f = proc {|x|x.to_f}
  def const(v)
    proc {|null|v}
  end
  def nth(n)
    proc {|*args|args[n]}
  end
  extend self
end

module FunctorMixin
  def flip
    proc {|x,y|call(y,x)}
  end
  def compose(other)
    proc {|*x|call(other.call(*x))}
  end
  alias << compose
  def >> (other)
    other << self
  end
  def curry
    FunctorMixin.make_curry(arity, &self)
  end
  def reverse_curry
    FunctorMixin.make_reverse_curry(arity, &self)
  end
  def uncurry
    return self unless arity == 1
    proc do |*args|
      result = self
      args.each do |a|
        result = result.call(a)
      end
      result
    end
  end
  def reverse_uncurry
    return self unless arity == 1
    proc do |*args|
      result = self
      args.reverse_each do |a|
        result = result.call(a)
      end
      result
    end
  end
  def repeat n
    proc do |*args|
      result = nil
      n.times {result = call(*args)}
      result
    end
  end
  alias * repeat
  def power n
    return Functors.const(nil) if n<=0
    return self if n==1
    proc do |*args|
      result = call(*args)
      (n-1).times {result = call(result)}
      result
    end
  end
  alias ^ power
  private_class_method
  def self.make_curry(arity, &block)
    return block if arity<=1
    proc do |x|
      make_curry(arity-1) do |*rest|
        block.call(*rest.insert(0, x))
      end
    end
  end
  def self.make_reverse_curry(arity, &block)
    return block if arity <= 1
    proc do |x|
      make_reverse_curry(arity-1) do |*rest|
        block.call(*rest << x)
      end
    end
  end
end
class Proc
  include FunctorMixin
end
class Method
  include FunctorMixin
end