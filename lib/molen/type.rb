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
            func_def.is_typed = true
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
            LLVM::Struct *([LLVM::Pointer(vtable_type)] + instance_variables.values.map(&:llvm_type))
        end

        def llvm_size
            8 # Size of a pointer
        end

        def vtable_type
            @vtable_type ||= begin
                struct = LLVM::Struct("#{name}_vtable_type")
                struct.element_types = [LLVM::Pointer(superclass ? superclass.vtable_type : struct), LLVM::Pointer(LLVM::Int8)]
                struct
            end
        end

        def ==(other)
            other.class == self.class and other.name == name and other.superclass == superclass and other.instance_variables == instance_variables
        end

        def instance_var_index(name)
            @instance_variables.keys.index(name) + 1 # Add 1 to skip the vtable
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
                builder.ret builder.load this
            end

            define_native_function "set_value", nil, ptr_type do |this, val|
                builder.store val, this
                builder.ret nil
            end

            define_native_function "__add", self, mod["Int"] do |this, offset|
                builder.ret builder.gep(this, [offset])
            end
        end

        def llvm_type
            LLVM::Pointer ptr_type.llvm_type
        end

        def llvm_size
            8 # Size of pointer
        end

        def ==(other)
            other.class == self.class and other.ptr_type == ptr_type
        end

        def castable_to?(other)
            return true, 0 if other.is_a?(PointerType) && ptr_type.castable_to?(other.ptr_type).first
            return true, 0 if other.is_a?(ObjectType)
            return true, 0 if other.is_a?(ArrayType) && other.element_type == ptr_type
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

    class ArrayType < Type
        attr_accessor :element_type

        def initialize(mod, el_type)
            super(el_type.name + "[]", nil)
            @element_type = el_type

            define_native_function "__index_get", el_type, mod["Int"] do |this, index|
                arr_buffer = builder.load builder.struct_gep this, 2
                builder.ret builder.load builder.gep arr_buffer, [index]
            end

            define_native_function "__index_set", el_type, mod["Int"], el_type do |this, index, obj|
                arr_buffer = builder.load builder.struct_gep this, 2
                builder.store obj, builder.gep(arr_buffer, [index])
                builder.ret obj
            end

            define_native_function "size", mod["Int"] do |this|
                builder.ret builder.load builder.struct_gep this, 0
            end

            define_native_function "capacity", mod["Int"] do |this|
                builder.ret builder.load builder.struct_gep this, 1
            end

            define_native_function "add", el_type, el_type do |this, arg|
                realloc_func = llvm_mod.functions["realloc"] || llvm_mod.functions.add("realloc", [LLVM::Pointer(LLVM::Int8), LLVM::Int], LLVM::Pointer(LLVM::Int8))

                the_func = builder.insert_block.parent
                resize_block = the_func.basic_blocks.append("resize")
                exit_block = the_func.basic_blocks.append("exit")

                arr_size = builder.load builder.struct_gep(this, 0)
                arr_cap = builder.load builder.struct_gep(this, 1)
                arr_el_size = el_type.llvm_type.is_a?(LLVM::Type) ? el_type.llvm_type.size : el_type.llvm_type.type.size
                builder.cond(builder.icmp(:eq, arr_size, arr_cap), resize_block, exit_block)

                builder.position_at_end resize_block
                new_capacity = builder.mul arr_cap, LLVM::Int(2)
                new_buffer_size = builder.mul new_capacity, builder.trunc(arr_el_size, LLVM::Int32)

                old_buffer = builder.load builder.struct_gep(this, 2)
                old_buffer = builder.bit_cast old_buffer, LLVM::Pointer(LLVM::Int8)
                new_buffer = builder.call realloc_func, old_buffer, new_buffer_size

                builder.store builder.bit_cast(new_buffer, LLVM::Pointer(el_type.llvm_type)), builder.struct_gep(this, 2)
                builder.store new_capacity, builder.struct_gep(this, 1)
                builder.br exit_block

                builder.position_at_end exit_block
                new_size = builder.add arr_size, LLVM::Int(1)
                builder.store new_size, builder.struct_gep(this, 0)

                arr_buffer = builder.load builder.struct_gep this, 2
                builder.store arg, builder.gep(arr_buffer, [arr_size])
                builder.ret arg
            end
        end

        def llvm_type
            LLVM::Pointer llvm_struct
        end

        def llvm_struct
            # First int is for size, second for capacity, third is the actual contents
            LLVM::Struct LLVM::Int, LLVM::Int, LLVM::Pointer(element_type.llvm_type)
        end

        def llvm_size
            4 + 4 + 8 # Size of two ints and a pointer
        end

        def ==(other)
            other.class == self.class and other.element_type == element_type
        end

        def castable_to?(other)
            return other == self, 0
        end
    end
end
