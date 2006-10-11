require 'import'
import :misc
class Module
  include DefHelper
end
class Expr
  def self.binary(*ops)
    ops.each do |op|
      define_method(op) do |other|
        BinaryExpr.new(self, op, other)
      end
    end
  end
  binary :+,:-,:*,:/,:%
  def -@
    PrefixExpr.new(:-, self)
  end
end
class LiteralExpr < Expr
  def_readable :lit
  def to_s
    @lit.to_s
  end
end
class WordExpr < Expr
  def_readable :name
  def to_s
    name
  end
end
class QualifiedColumnExpr < Expr
  def_readable :owner, :col
  def to_s
    "#{owner}.#{col}"
  end
end
class WildcardExpr < Expr
  Instance = WildcardExpr.new
  def to_s
    '*'
  end
end
class BinaryExpr < Expr
  def_readable :left, :op, :right
  def to_s
    "(#{left} #{op} #{right})"
  end
end
class PostfixExpr < Expr
  def_readable :expr, :op
  def to_s
    "(#{expr} #{op})"
  end
end
class PrefixExpr < Expr
  def_readable :op, :expr
  def to_s
    "(#{op} #{expr})"
  end
end
def cases_string cases, default, result
    cases.each do |cond, val|
      result << " when #{cond}: #{val}"
    end
    unless default.nil?
      result << " else #{default}"
    end
    result << " end"
    result
end
class SimpleCaseExpr < Expr
  def_readable :expr, :cases, :default
  def to_s
    cases_string cases, default, "case #{expr}"
  end
end
class CaseExpr < Expr
  def_readable :cases, :default
  def to_s
    cases_string cases, default, 'case'
  end
end


#############Relations######################
class Relation
  def as_inner
    to_s
  end
end
class TableRelation < Relation
  def_readable :table
  def to_s
    table
  end
end
class SelectRelation < Relation
  def_readable :projection, :table
  def to_s
    "select #{projection.join(', ')} from #{table.as_inner}"
  end
  def as_inner
    "(#{self})"
  end
end
class AliasRelation < Relation
  def_readable :relation, :name
  def to_s
    "#{relation.as_inner} AS #{name}"
  end
end