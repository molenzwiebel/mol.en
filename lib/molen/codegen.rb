require "llvm/core"
require 'llvm/execution_engine'
require 'llvm/transforms/scalar'
require 'llvm/transforms/ipo'
require 'llvm/transforms/vectorize'
require 'llvm/transforms/builder'

module Molen

    def run(src, filename = "unknown_file")
        Molen.run(src, filename)
    end

    def self.run(src, filename = "unknown_file")
        mod = generate(src, filename)
        mod.verify

        LLVM.init_jit

        engine = LLVM::JITCompiler.new mod
        optimizer = LLVM::PassManager.new engine
        optimizer << :arg_promote << :gdce << :global_opt << :gvn << :reassociate << :instcombine << :basicaa << :jump_threading << :simplifycfg << :inline << :mem2reg << :loop_unroll << :loop_rotate << :loop_deletion << :tailcallelim
        5.times { optimizer.run mod }
        mod.verify

        engine.run_function mod.functions["main"]
    end

    def generate(src, filename = "unknown_file")
        Molen.generate(src, filename)
    end

    def self.generate(src, filename = "unknown_file")
        program = Molen::Program.new
        body = type parse(src, filename), program

        visitor = GeneratingVisitor.new(program, body.type || VoidType.new)
        body.accept visitor
        visitor.builder.ret nil

        visitor.mod
    end

    class GeneratingVisitor < Visitor
        VOID_PTR = LLVM::Pointer(LLVM::Int8)
        attr_accessor :program, :mod, :builder

        def initialize(program, ret_type)
            @program = program

            @mod     = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = mod.functions.add "molen_main", [], ret_type.llvm_type
            main_func.linkage = :internal
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            mod.functions.add("main", [], LLVM::Int32) do |f|
                f.basic_blocks.append.build do |b|
                    b.call mod.functions["molen_main"]
                    b.ret LLVM::Int(0)
                end
            end

            @type_infos = {}
            @vtables = {}
            @object_allocator_functions = {}

            @variable_pointers = {}
            @function_pointers = {}
        end

        def visit_int(node)
            LLVM::Int32.from_i node.value
        end

        def visit_double(node)
            LLVM::Double node.value
        end

        def visit_bool(node)
            node.value ? LLVM::TRUE : LLVM::FALSE
        end

        def visit_str(node)
            #allocate_string builder.global_string_pointer(node.value)
        end

        def visit_long(node)
            LLVM::Int64.from_i node.value
        end

        def visit_identifier(node)
            builder.load @variable_pointers[node.value], node.value
        end

        def visit_body(node)
            node.each {|n| n.accept self}
        end

        def visit_size_of(node)
            type = node.target_type.llvm_type
            type = node.target_type.llvm_struct if node.target_type.is_a?(StructType)

            type.is_a?(LLVM::Type) ? type.size : type.type.size
        end

        def visit_member_access(node)
            builder.load member_to_ptr(node), node.field.value
        end

        def visit_cast(node)
            builder.bit_cast node.target.accept(self), node.type.llvm_type
        end

        def visit_pointer_of(node)
            ptr = @variable_pointers[node.target.value]
            ptr = builder.load(ptr) if node.target.type.is_a? StructType
            return ptr
        end

        def visit_assign(node)
            if node.target.is_a?(Identifier) then
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                unless @variable_pointers[node.target.value]
                    @variable_pointers[node.target.value] = builder.alloca(node.type.llvm_type, node.target.value)
                end

                builder.store val, @variable_pointers[node.target.value]
                return val
            elsif node.target.is_a?(MemberAccess) then
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                builder.store val, member_to_ptr(node.target)
                return val
            end
        end

        def visit_return(node)
            return builder.ret(builder.int2ptr(LLVM::Int(0), builder.insert_block.parent.function_type.return_type)) if node.type.is_a?(VoidType)
            builder.ret node.value.accept(self)
        end

        private
        def member_to_ptr(node)
            ptr_to_obj = node.object.accept(self)
            index = node.object.type.var_index node.field.value

            builder.struct_gep ptr_to_obj, index
        end

        def memset(pointer, value, size)
            memset_func = mod.functions['memset'] || mod.functions.add('memset', [VOID_PTR, LLVM::Int, LLVM::Int], VOID_PTR)

            pointer = builder.bit_cast pointer, VOID_PTR
            builder.call memset_func, pointer, value, builder.trunc(size, LLVM::Int32)
        end

        def generate_object_allocator(type)
            old_pos = builder.insert_block

            @object_allocator_functions[type] = func = mod.functions.add("_allocate_#{type.name}", [], type.llvm_type)
            func.linkage = :internal
            builder.position_at_end func.basic_blocks.append("entry")

            allocated_struct = builder.malloc type.llvm_struct, type.name
            memset allocated_struct, LLVM::Int(0), type.llvm_struct.size
            populate_vtable allocated_struct, type if type.is_a?(ObjectType)
            builder.ret allocated_struct

            builder.position_at_end old_pos
            func
        end

        def get_or_create_type_info(type)
            return @type_infos[type] if @type_infos[type]

            parent_ptr = type.parent_type ? builder.bit_cast(get_or_create_type_info(type.parent_type), VOID_PTR) : builder.int2ptr(LLVM::Int(0), VOID_PTR)
            @type_infos[type] = add_global("typeinfo.#{type.name}", LLVM::ConstantStruct.const([parent_ptr, builder.global_string_pointer(type.name)]))
        end

        def get_or_create_vtable(type)
            return @vtables[type] if @vtables[type]

            used_funcs = type.vtable_functions.map do |f|
                generate_function(f) unless @function_pointers[f]
                builder.bit_cast(@function_pointers[f], VOID_PTR)
            end

            @vtables[type] = add_global("vtable.#{type.name}", LLVM::ConstantArray.const(VOID_PTR, used_funcs))
        end

        def populate_vtable(allocated_struct, type)
            builder.store get_or_create_vtable(type).bitcast_to(ObjectType::VTABLE_PTR), builder.struct_gep(allocated_struct, 0)
            builder.store get_or_create_type_info(type).bitcast_to(ObjectType::TYPEINFO_PTR), builder.struct_gep(allocated_struct, 1)
        end

        def add_global(name, val)
            mod.globals.add(val, name) do |var|
                var.linkage = :private
                var.global_constant = true
                var.initializer = val
            end
        end
    end
end
