
module Molen
    class Type
        attr_accessor :name, :llvm_type, :vars
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
            @llvm_struct_type ||= LLVM::Struct *vars.values
        end

        def ==(other)
            other.class == self.class && other.name == name && other.superclass == superclass
        end

        # Checks if this type can be casted to the provided type automatically in function calls.
        # This is true if `other` is this class or a superclass of this class. Returns
        # (true, distance from this class) if true, returns (false, -1) otherwise
        def castable_to(other)
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
        def initialize(name, llvm_type)
            @name = name

            @llvm_type = llvm_type
            @vars = {}
        end

        def llvm_type
            @llvm_type
        end

        def ==(other)
            other.class == self.class && other.name == name && other.llvm_type == llvm_type
        end

        def castable_to(other)
            other == self
        end
    end

    class ArrayType < Type
    end
end