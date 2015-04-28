
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["Int"] = PrimitiveType.new "Int", LLVM::Int32
            self["Double"] = PrimitiveType.new "Double", LLVM::Double
            self["String"] = PrimitiveType.new "String", LLVM::Pointer(LLVM::Int8)
            self["Bool"] = PrimitiveType.new "Bool", LLVM::Int1
        end

        def [](key)
            types[key]
        end

        def []=(key, val)
            types[key] = val
        end
    end
end
