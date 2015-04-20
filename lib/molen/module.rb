
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["Object"] = ObjectType.new "Object"
            self["Bool"] = PrimitiveType.new "Bool", self["Object"], LLVM::Int1
            self["Int"] = PrimitiveType.new "Int", self["Object"], LLVM::Int32
            self["Double"] = PrimitiveType.new "Double", self["Object"], LLVM::Double
            self["String"] = PrimitiveType.new "String", self["Object"], LLVM::Pointer(LLVM::Int8)
        end

        def [](q)
            @types[q]
        end

        def []=(a, b)
            @types[a] = b
        end
    end
end