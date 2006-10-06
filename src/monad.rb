module Monad
  attr_reader :obj
  
  def initMonad(m, v)
    @monad = m;
    @obj = v;
  end
  def value v
    @monad.value v
  end
  def bind(&binder)
    @monad.bind(@obj, &binder)
  end
  def seq(other)
    if @monad.respond_to? :seq
      @monad.seq(other)
    else bind {|x|other}
    end
  end
  def map(&mapper)
    bind do |v|
      result = mapper.call v;
      value(result);
    end
  end
  def plus other
    @monad.mplus(@obj, other.obj)
  end
end