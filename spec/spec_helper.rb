require File.expand_path("../../lib/molen",  __FILE__)

include Molen

class Object
    def return
        Return.new self
    end
end

class NilClass
    def literal
        Null.new
    end
end

class Fixnum
    def literal
        Int.new self
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
        Constant.new self
    end

    def var
        InstanceVariable.new self
    end
end

class Float
    def literal
        Double.new self
    end
end
