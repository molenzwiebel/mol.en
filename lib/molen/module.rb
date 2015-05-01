
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["Object"] = object = ObjectType.new "Object"

            self["Int"] = PrimitiveType.new "Int", object, LLVM::Int32
            self["Double"] = PrimitiveType.new "Double", object, LLVM::Double
            self["String"] = PrimitiveType.new "String", object, LLVM::Pointer(LLVM::Int8)
            self["Bool"] = PrimitiveType.new "Bool", object, LLVM::Int1

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
