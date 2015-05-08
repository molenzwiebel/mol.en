
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["Object"] = object = ObjectType.new "Object"

            self["Bool"] = PrimitiveType.new "Bool", LLVM::Int1, 1
            self["Char"] = PrimitiveType.new "Char", LLVM::Int8, 2
            self["Int"] = PrimitiveType.new "Int", LLVM::Int32, 4
            self["Long"] = PrimitiveType.new "Int", LLVM::Int64, 8
            self["Double"] = PrimitiveType.new "Double", LLVM::Double, 8

            self["String"] = ObjectType.new "String", object
            self["String"].instance_variables.define "value", PointerType.new(self, self["Char"])

            self["*Void"] = PointerType.new self, self["Char"]

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
