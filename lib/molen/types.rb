
module Molen
    class Type
        attr_accessor :name, :llvm_type, :size, :vars
    end

    class ObjectType < Type
        attr_accessor :superclass

        def initialize(name, supertype = nil)
            @name = name
            @superclass = supertype

            @vars = {}
        end

        def llvm_type
            @llvm_type ||= LLVM::Pointer llvm_struct
        end

        def llvm_struct
            @llvm_struct_type ||= LLVM::Struct *vars.map(&:llvm_type)
        end

        def llvm_size
            8 # Int8, a pointer
        end

        def ==(other)
            other.class == self.class && other.name == name && other.superclass == superclass
        end
    end

    class PrimitiveType < ObjectType
        def initialize(name, superclass, llvm_type, llvm_size)
            super name, superclass
            @llvm_type = llvm_type
            @size = llvm_size
        end

        def llvm_type
            @llvm_type
        end

        def llvm_size
            @size
        end

        def ==(other)
            super(other) && other.llvm_type == llvm_type && other.size == size
        end
    end

    class ArrayType < Type
    end
end