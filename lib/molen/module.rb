
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["Object"] = ObjectType.new "Object"

            self["String"] = ObjectType.new "String", self["Object"]
            self["String"].vars["value"] = LLVM::Pointer(LLVM::Int8)

            self["Boolean"] = ObjectType.new "Boolean", self["Object"]
            self["Boolean"].vars["value"] = LLVM::Int1

            self["Integer"] = ObjectType.new "Integer", self["Object"]
            self["Integer"].vars["value"] = LLVM::Int32

            self["Double"] = ObjectType.new "Double", self["Object"]
            self["Double"].vars["value"] = LLVM::Double

            self["bool"] = PrimitiveType.new "bool", LLVM::Int1
            self["int"] = PrimitiveType.new "int", LLVM::Int32
            self["double"] = PrimitiveType.new "double", LLVM::Double
        end

        def [](q)
            @types[q]
        end

        def []=(a, b)
            @types[a] = b
        end
    end
end