
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}

            self["Object"] = object = ObjectType.new "Object"

            self["cint1"] = cint1 = PrimitiveType.new "cint1", LLVM::Int1, 1
            self["cint8"] = cint8 = PrimitiveType.new "cint8", LLVM::Int8, 1
            self["cuint8"] = cuint8 = PrimitiveType.new "cuint8", LLVM::UInt8, 1
            self["cint16"] = cint16 = PrimitiveType.new "cint16", LLVM::Int16, 2
            self["cuint16"] = cuint16 = PrimitiveType.new "cuint16", LLVM::UInt16, 2
            self["cint32"] = cint32 = PrimitiveType.new "cint32", LLVM::Int32, 4
            self["cuint32"] = cuint32 = PrimitiveType.new "cuint32", LLVM::UInt32, 4
            self["cint64"] = cint64 = PrimitiveType.new "cint64", LLVM::Int64, 8
            self["cuint64"] = cuint64 = PrimitiveType.new "cuint64", LLVM::UInt64, 8

            self["cfloat"] = cfloat = PrimitiveType.new "cfloat", LLVM::Float, 4
            self["cdouble"] = cdouble = PrimitiveType.new "cdouble", LLVM::Float, 8

            self["cstr"] = cstr = PrimitiveType.new "cstr", LLVM::Pointer(LLVM::Int8), 8

            self["Int"] = int = ObjectType.new "Int", object
            self["Double"] = double = ObjectType.new "Double", object
            self["String"] = string = ObjectType.new "String", object
            self["Bool"] = bool = ObjectType.new "Bool", object

            int.instance_variables.define "value", cint32
            double.instance_variables.define "value", cdouble
            string.instance_variables.define "value", cstr
            bool.instance_variables.define "value", cint1

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
