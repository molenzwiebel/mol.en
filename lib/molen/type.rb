require 'llvm/core'
require 'llvm/execution_engine'

module Molen
    class Type
        attr_accessor :name, :superclass, :functions, :class_functions

        def initialize(name, supercl)
            @name = name
            @superclass = supercl
            @functions = supercl ? Scope.new(supercl.functions) : Scope.new()
            @class_functions = {} # Don't inherit class functions
        end

        def llvm_type
            raise "Unimplemented llvm_type on #{self.class.name}"
        end

        def llvm_size
            raise "Unimplemented llvm_size on #{self.class.name}"
        end

        def castable_to?(other)
            raise "Unimplemented castable_to on #{self.class.name}"
        end

        def inheritance_chain
            ret = [self]
            type = self
            while type = type.superclass
                ret << type
            end
            ret
        end

        def create_func(name, return_type, *args, &block)
            body = NativeBody.new block
            func_def = Function.new ClassDef.new(nil, nil, [], []), name, return_type, args.each_with_index.map{|type, id| FunctionArg.new "arg#{id.to_s}", type}, nil
            func_def.body = body
            func_def.owner.type = self
            func_def.is_prototype_typed = true
            return func_def
        end

        def define_native_function(name, return_type, *args, &block)
            f = create_func name, return_type, *args, &block
            functions.has_local_key?(name) ? functions[name] << f : functions.define(name, [f])
        end

        def define_static_native_function(name, return_type, *args, &block)
            class_functions[name] = (class_functions[name] || []) << create_func(name, return_type, *args, &block)
        end
    end

    class NativeBody < ASTNode
        attr_accessor :block
        attr_eq :block

        def initialize(bl)
            @block = bl
        end

        def definitely_returns?
            true
        end
    end

    class ObjectType < Type
        VTABLE_PTR = LLVM::Pointer(LLVM::Pointer(LLVM::Function([], LLVM::Int, varargs: true)))
        TYPEINFO_PTR = LLVM::Pointer(LLVM::Struct(GeneratingVisitor::VOID_PTR, GeneratingVisitor::VOID_PTR, "_typeinfo"))

        attr_accessor :generic_types, :instance_variables, :used_functions

        def initialize(name, supertype = nil, types = {})
            raise "Expected superclass of #{name} to be an object, #{supertype.to_s} received." if supertype and !supertype.is_a?(ObjectType)
            name = name + "<" + types.values.map(&:name).join(", ") + ">" if types.size > 0
            super name, supertype

            @instance_variables = supertype ? Scope.new(supertype.instance_variables) : Scope.new
            @used_functions = []
            @generic_types = {}
        end

        def llvm_type
            LLVM::Pointer llvm_struct
        end

        def llvm_struct
            LLVM::Struct *([VTABLE_PTR, TYPEINFO_PTR] + instance_variables.values.map(&:llvm_type))
        end

        def llvm_size
            8 # Size of a pointer
        end

        def ==(other)
            other.class == self.class and other.name == name and other.superclass == superclass and other.instance_variables == instance_variables
        end

        def use_function(func)
            existing = used_functions.count {|x| (x.owner && func.owner ? x.owner.type == func.owner.type : true) && x == func} > 0
            @used_functions << func unless existing
        end

        def used_functions
            (superclass ? superclass.used_functions : []) + @used_functions
        end

        def vtable_functions
            used_functions.map do |func|
                next func if func.overriding_functions.size == 0
                next func unless func.overriding_functions[name]
                func.overriding_functions[name]
            end
        end

        def instance_var_index(name)
            @instance_variables.keys.index(name) + 2 # Add 1 to skip the vtable and type info
        end

        def function_index(func)
            used_functions.index func
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

    class StructType < Type
        attr_accessor :instance_variables

        def initialize(name, vars)
            super name, nil

            @instance_variables = vars
        end

        def llvm_type
            LLVM::Pointer llvm_struct
        end

        def llvm_struct
            LLVM::Struct *(instance_variables.values.map(&:llvm_type))
        end

        def ==(other)
            other.class == self.class and other.name == name and other.instance_variables == instance_variables
        end

        def instance_var_index(name)
            instance_variables.keys.index(name)
        end

        def castable_to?(other)
            return false, 0 unless other.is_a?(StructType)
            return true, 0 if other == self
            return false, 0 if other.instance_variables.size > instance_variables.size

            slice = instance_variables.values.first(other.instance_variables.size)
            return slice == other.instance_variables.values, 0
        end
    end

    class PrimitiveType < Type
        attr_accessor :type

        def initialize(name, llvm_type, llvm_size)
            super name, nil
            @type = llvm_type
            @size = llvm_size
        end

        def llvm_type
            @type
        end

        def llvm_size
            @size
        end

        def fp?
            name == "Double" || name == "Float"
        end

        def ==(other)
            other.class == self.class and other.name == name and other.type == type
        end

        def castable_to?(other)
            return other == self, 0
        end
    end

    class PointerType < Type
        attr_accessor :ptr_type

        def initialize(mod, ptr_type)
            super "*" + ptr_type.name, nil
            @ptr_type = ptr_type

            define_native_function "value", ptr_type do |this|
                if ptr_type.is_a?(StructType) then
                    builder.ret this
                else
                    builder.ret builder.load this
                end
            end

            define_native_function "set_value", nil, ptr_type do |this, val|
                builder.store val, this
                builder.ret nil
            end

            define_native_function "__add", self, mod["Int"] do |this, offset|
                builder.ret builder.gep(this, [offset])
            end

            ptr = self
            define_native_function "realloc", self, mod["Int"] do |this, new_size|
                realloc_func = llvm_mod.functions["realloc"] || llvm_mod.functions.add("realloc", [LLVM::Pointer(LLVM::Int8), LLVM::Int], LLVM::Pointer(LLVM::Int8))

                casted_buffer = builder.bit_cast this, LLVM::Pointer(LLVM::Int8)
                new_buffer = builder.call realloc_func, casted_buffer, new_size
                builder.ret builder.bit_cast new_buffer, ptr.llvm_type
            end
        end

        def llvm_type
            ptr_type.is_a?(StructType) ? ptr_type.llvm_type : LLVM::Pointer(ptr_type.llvm_type)
        end

        def llvm_size
            8 # Size of pointer
        end

        def ==(other)
            other.class == self.class and other.ptr_type == ptr_type
        end

        def castable_to?(other)
            return true, 0 if other.is_a?(PointerType)
            return false, -1
        end
    end

    class ExternalType < Type
        attr_accessor :locations

        def initialize(name)
            super name, nil
            @locations = []
        end

        def ==(other)
            other.class == self.class and other.name == name and other.location == location
        end

        def castable_to?(other)
            return other == self, 0
        end
    end
end
