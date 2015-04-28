
module Molen
    class Type
        attr_accessor :name, :superclass, :functions

        def initialize(name, supercl)
            @name = name
            @superclass = supercl
            @functions = supercl ? Scope.new(supercl.functions) : Scope.new()
        end

        def llvm_type
            raise "Unimplemented llvm_type?"
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
            LLVM::Struct *(vars.values.map(&:llvm_type))
        end

        def ==(other)
            other.class == self.class and other.name == name and other.superclass == superclass and other.instance_variables == instance_variables
        end
    end

    class PrimitiveType < Type
        attr_accessor :type

        def initialize(name, llvm_type)
            super name, nil
            @type = llvm_type
        end

        def llvm_type
            # Primitives are pointers to their type so they can support actual null, instead of a workaround.
            LLVM::Pointer @type
        end

        def ==(other)
            other.class == self.class and other.name == name and other.type == type
        end
    end
end
