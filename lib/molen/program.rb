require 'llvm/core'

module Molen
    class Program
        attr_accessor :types, :functions

        def initialize
            @types = {}
            @functions = {}

            @types["Bool"] = PrimitiveType.new "Bool", LLVM::Int1
            @types["Char"] = PrimitiveType.new "Char", LLVM::Int8
            @types["Short"] = PrimitiveType.new "Short", LLVM::Int16
            @types["Int"] = PrimitiveType.new "Int", LLVM::Int32
            @types["Long"] = PrimitiveType.new "Long", LLVM::Int64
            @types["Float"] = PrimitiveType.new "Float", LLVM::Float
            @types["Double"] = PrimitiveType.new "Double", LLVM::Double

            @types["Object"] = ObjectType.new "Object", nil
            @types["String"] = ObjectType.new "String", object
            #string.vars['pointer'] = PointerType.new char
        end

        def method_missing(name, *args)
            type = types[name.to_s.capitalize]
            return type if type
            super
        end

        def lookup_type(name)
            types[name]
        end
    end
end
