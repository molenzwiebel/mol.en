require 'llvm/core'
require 'llvm/execution_engine'

module Molen
    class Type
        attr_accessor :name, :superclass, :functions

        def initialize(name, supercl)
            @name = name
            @superclass = supercl
            @functions = supercl ? Scope.new(supercl.functions) : Scope.new()
        end

        def llvm_type
            raise "Unimplemented llvm_type on #{self.class.name}?"
        end

        def castable_to?(other)
            raise "Unimplemented castable_to on #{self.class.name}"
        end

        def define_native_function(name, return_type, *args, &block)
            body = NativeBody.new block
            func_def = Function.new ClassDef.new(nil, nil, [], []), name, return_type, args.each_with_index.map{|type, id| FunctionArg.new "arg#{id.to_s}", type}, nil
            func_def.body = body
            func_def.owner.type = self
            functions.has_local_key?(name) ? functions[name] << func_def : functions.define(name, [func_def])
        end
    end

    class NativeBody < ASTNode
        attr_accessor :block
        attr_eq :block

        def initialize(bl)
            @block = bl
        end
    end

    class ObjectType < Type
        attr_accessor :instance_variables

        def initialize(name, supertype = nil)
            raise "Expected superclass of #{name} to be an object, #{supertype.to_s} received." if supertype and !supertype.is_a?(ObjectType)
            super name, supertype

            @instance_variables = supertype ? Scope.new(supertype.instance_variables) : Scope.new
        end

        def llvm_type
            LLVM::Pointer llvm_struct
        end

        def llvm_struct
            LLVM::Struct *(instance_variables.values.map(&:llvm_type))
        end

        def ==(other)
            other.class == self.class and other.name == name and other.superclass == superclass and other.instance_variables == instance_variables
        end

        def instance_var_index(name)
            @instance_variables.keys.index name
        end

        def castable_to?(other)
            return true, 0 if other == self
            clazz = superclass
            dist = 1
            until clazz.nil?
                return true, dist if other == clazz
                dist += 1
                clazz = clazz.superclass
            end
            return false, -1
        end
    end

    class PrimitiveType < Type
        attr_accessor :type

        def initialize(name, supert, llvm_type)
            super name, supert
            @type = llvm_type
        end

        def llvm_type
            # TODO: Later maybe? (Primitives are pointers to their type so they can support actual null, instead of a workaround.)
            @type
        end

        def ==(other)
            other.class == self.class and other.name == name and other.type == type
        end

        def castable_to?(other)
            return other == self, 0
        end
    end
end
