require File.expand_path("../../lib/molen",  __FILE__)
include Molen

class NilClass
    def literal
        Null.new
    end

    def type
        UnresolvedVoidType.new
    end
end

class Fixnum
    def literal
        Int.new self
    end

    def long
        Long.new self
    end
end

class TrueClass
    def literal
        Bool.new true
    end
end

class FalseClass
    def literal
        Bool.new false
    end
end

class String
    def literal
        Str.new self
    end

    def ident
        Identifier.new self
    end

    def const
        Constant.new [self]
    end

    def var
        MemberAccess.new "this".ident, ident
    end

    def type
        UnresolvedSimpleType.new [self]
    end
end

class ASTNode
    def ptr
        PointerOf.new self
    end

    def return
        Return.new self
    end

    def to_bool_call
        Call.new(self, "to_bool", [])
    end
end

class UnresolvedType
    def ptr
        UnresolvedPointerType.new self
    end
end

class Float
    def literal
        Double.new self
    end
end

class Array
    def new
        NewArray.new self
    end

    def const
        Constant.new self
    end
end
