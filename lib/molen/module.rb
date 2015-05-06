
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["Object"] = object = ObjectType.new "Object"

            self["Int"] = PrimitiveType.new "Int", LLVM::Int32, 4
            self["Double"] = PrimitiveType.new "Double", LLVM::Double, 8
            self["String"] = PrimitiveType.new "String", LLVM::Pointer(LLVM::Int8), 8
            self["Bool"] = PrimitiveType.new "Bool", LLVM::Int1, 1
            self["Pointer"] = PrimitiveType.new "Pointer", LLVM::Pointer(LLVM::Int8), 8

            add_natives
        end

        def [](key)
            types[key]
        end

        def []=(key, val)
            types[key] = val
        end
    end
end
