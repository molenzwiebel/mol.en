
module Molen
    class Type
        attr_accessor :name

        def initialize(name)
            @name = name
        end

        def llvm_type
            raise "Unimplemented llvm_type on #{name}"
        end

        def upcastable_to?(other)
            raise "Unimplemented upcastable_to? on #{name}"
        end

        def explicitly_castable_to?(other)
            raise "Unimplemented explicitly_castable_to? on #{name}"
        end

        def metaclass
            @metaclass ||= Metaclass.new(self)
        end

        def ==(other)
            other.class == self.class && other.name == name
        end
    end

    # A container type is able to contain other types. Sorta
    # like ruby modules or java packages.
    class ContainerType < Type
        attr_accessor :types

        def initialize(name)
            super name

            @types = {}
        end

        def ==(other)
            super && other.types == types
        end
    end

    class ClassType < ContainerType
        attr_accessor :parent_type, :functions

        def initialize(name, parent)
            super name

            @parent_type = parent
            @functions = parent ? ParentHash.new(parent.functions) : Hash.new { |h, k| h[k] = [] }
        end

        def inheritance_chain
            [self] + (parent_type ? parent_type.inheritance_chain : [])
        end

        def ==(other)
            super && other.parent_type == parent_type && other.functions == functions
        end
    end

    class PrimitiveType < ClassType
        attr_accessor :llvm_type

        def initialize(name, llvm_type)
            super name, nil

            @llvm_type = llvm_type
        end

        def llvm_type
            @llvm_type
        end

        def ==(other)
            parent && other.name == name && other.llvm_type == llvm_type && other.functions == functions
        end

        def upcastable_to?(other)
            return other.llvm_type == llvm_type, 0
        end

        def explicitly_castable_to?(other)
            upcastable_to?(other).first
        end
    end

    class ObjectType < ClassType
        attr_accessor :vars

        def initialize(name, parent)
            super name, parent

            @vars = parent ? ParentHash.new(parent.vars) : {}
        end

        def llvm_type
            LLVM::Pointer llvm_struct
        end

        def llvm_struct
            @llvm_struct ||= begin
                llvm_struct = LLVM::Struct(name)
                llvm_struct.element_types = vars.values.map(&:llvm_type)
                llvm_struct
            end
        end

        def ==(other)
            super && other.vars == vars
        end

        def upcastable_to?(other)
            return other.is_a?(ObjectType) && inheritance_chain.include?(other), inheritance_chain.index(other)
        end

        def explicitly_castable_to?(other)
            return false unless other.is_a?(ObjectType)

            is_upcast = upcastable_to?(other).first
            return true if is_upcast

            return other.inheritance_chain.include?(self)
        end
    end

    class Metaclass < Type
        attr_accessor :type, :functions

        def initialize(type)
            super type.name + ":Metaclass"

            @type = type
            @functions = {}
        end

        def ==(other)
            other.class == self.class && other.type == type && other.functions == functions
        end

        def upcastable_to?(other)
            return other == self, 0
        end

        def explicitly_castable_to?(other)
            upcastable_to?(other).first
        end
    end
end
