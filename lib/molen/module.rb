
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["bool"] = PrimitiveType.new "bool", LLVM::Int1
            self["int"] = PrimitiveType.new "int", LLVM::Int32
            self["double"] = PrimitiveType.new "double", LLVM::Double
            self["str"] = PrimitiveType.new "str", LLVM::Pointer(LLVM::Int8)

            self["Object"] = ObjectType.new "Object"

            self["String"] = ObjectType.new "String", self["Object"]
            self["String"].vars.define "value", self["str"]

            self["Boolean"] = ObjectType.new "Boolean", self["Object"]
            self["Boolean"].vars.define "value", self["bool"]

            self["Integer"] = ObjectType.new "Integer", self["Object"]
            self["Integer"].vars.define "value", self["int"]

            self["Double"] = ObjectType.new "Double", self["Object"]
            self["Double"].vars.define "value", self["double"]
        end

        def [](q)
            @types[q]
        end

        def []=(a, b)
            @types[a] = b
        end
    end
end