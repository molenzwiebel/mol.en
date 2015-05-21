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
            allocate_string builder.global_string_pointer(node.value)
        end

        def visit_long(node)
            LLVM::Int64.from_i node.value
        end

        def visit_identifier(node)
            return @variable_pointers[node.value] if node.value == "this"
            builder.load @variable_pointers[node.value], node.value
        end

        def visit_body(node)
            node.each {|n| n.accept self}
        end

        def visit_null(node)
            builder.int2ptr LLVM::Int(0), LLVM::Pointer(LLVM::Int8)
        end

        def visit_native_body(node)
            instance_exec *builder.insert_block.parent.params.to_a, &node.block
        end

        def visit_size_of(node)
            type = node.target_type.llvm_type
            type = node.target_type.llvm_struct if node.target_type.is_a?(StructType)

            type.is_a?(LLVM::Type) ? type.size : type.type.size
        end

        def visit_member_access(node)
            builder.load member_to_ptr(node)
        end

        def visit_cast(node)
            builder.bit_cast node.target.accept(self), node.type.llvm_type
        end

        def visit_pointer_of(node)
            ret = nil
            if node.target.is_a?(Identifier) then
                ptr = @variable_pointers[node.target.value]
                ptr = builder.load(ptr) if node.target.type.is_a? StructType
                ret = ptr
            elsif node.target.is_a?(MemberAccess) then
                ret = member_to_ptr(node.target)
            end
            ret = builder.load(ret) if node.target.type.is_a? StructType
            ret
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
            return builder.ret(nil) if node.type.is_a?(VoidType) && builder.insert_block.parent.function_type.return_type == LLVM.Void
            return builder.ret(builder.int2ptr(LLVM::Int(0), builder.insert_block.parent.function_type.return_type)) if node.type.is_a?(VoidType)
            builder.ret builder.bit_cast(node.value.accept(self), builder.insert_block.parent.function_type.return_type)
        end

        def visit_new_anonymous_function(node)
            old_pos = builder.insert_block

            struct = builder.alloca node.type.struct_type
            var_struct = builder.alloca node.type.var_struct
            node.type.captured_vars.each_with_index do |(k,v), index|
                val = @variable_pointers[k]
                val = builder.load(val) unless v.is_a?(PrimitiveType) || v.is_a?(PointerType) || k == "this"
                builder.store val, builder.struct_gep(var_struct, index)
            end
            builder.store builder.bit_cast(var_struct, VOID_PTR), builder.struct_gep(struct, 0)

            func = mod.functions.add("__lambda", node.type.function_type)
            func.linkage = :internal
            builder.position_at_end func.basic_blocks.append("entry")

            with_new_scope(false) do
                scope_ptr = builder.bit_cast(func.params[0], LLVM::Pointer(node.type.var_struct), "__lambda_scope")

                node.type.captured_vars.each_with_index do |(k,v), index|
                    ptr = builder.alloca v.llvm_type, k
                    @variable_pointers[k] = ptr
                    val = builder.load builder.struct_gep(scope_ptr, index)
                    val = builder.load val unless v.is_a?(ObjectType) || v.is_a?(StructType) || v.is_a?(FunctionType)
                    builder.store val, ptr
                end

                node.args.each_with_index do |arg, i|
                    func.params[i + 1].name = arg.name
                    ptr = builder.alloca arg.type.llvm_type, arg.name
                    @variable_pointers[arg.name] = ptr
                    builder.store func.params[i + 1], ptr
                end

                node.body.accept self
                builder.ret nil if node.type.return_type.is_a?(VoidType) and not node.body.returns?
            end

            builder.position_at_end old_pos
            builder.store func, builder.struct_gep(struct, 1)
            struct
        end

        def visit_new(node)
            allocator = @object_allocator_functions[node.type]
            allocator = generate_object_allocator(node.type) unless allocator

            allocated_struct = builder.call allocator

            if node.target_constructor then
                create_func = @function_pointers[node.target_constructor]
                create_func = generate_function(node.target_constructor) unless create_func
                casted_this = builder.bit_cast allocated_struct, node.target_constructor.owner_type.llvm_type

                args = [casted_this]
                node.args.each_with_index do |arg, i|
                    val = arg.accept(self)
                    val = builder.bit_cast val, node.target_constructor.args[i].type.llvm_type
                    args << val
                end

                builder.call create_func, *args
            end

            allocated_struct
        end

        def visit_call(node)
            # Setup arguments and cast them if needed.
            args = []
            node.args.each_with_index do |arg, i|
                val = arg.accept(self)
                val = builder.bit_cast val, node.target_function.args[i].type.llvm_type if arg.type != node.target_function.args[i].type
                args << val
            end

            if node.object && node.object.type.pass_as_this? then
                obj = node.object.accept(self)
                generate_null_check(node, node.object.type, obj) unless node.name == "to_bool" || node.name == "is_null"
                casted_this = builder.bit_cast obj, node.target_function.owner_type.llvm_type
                args = [casted_this] + args
            end

            if node.object && node.object.type.is_a?(ObjectType) && node.target_function.overriding_functions.size > 0 then
                return generate_vtable_invoke args, node
            else
                func = @function_pointers[node.target_function]
                func = generate_function(node.target_function) unless func

                ret_ptr = builder.call func, *args
                return ret_ptr if func.function_type.return_type != LLVM.Void
                return nil
            end
        end

        def generate_vtable_invoke(args, node)
            func = @function_pointers[node.target_function]
            func = generate_function(node.target_function) unless func

            vtable_ptr = builder.bit_cast args[0], LLVM::Pointer(LLVM::Pointer(LLVM::Pointer(func.function_type)))
            vtable = builder.load vtable_ptr, "vtable"

            func_ptr = builder.inbounds_gep(vtable, [LLVM::Int64.from_i(node.object.type.func_index(node.target_function))])
            loaded_func = builder.load func_ptr

            res = builder.call loaded_func, *args
            return res if func.function_type.return_type != LLVM.Void
            return nil
        end

        def generate_function(node)
            args = node.args
            args = [FunctionArg.new("this", node.owner_type)] + args if node.owner_type && node.owner_type.pass_as_this?
            llvm_arg_types = args.map(&:type).map(&:llvm_type)

            if node.is_a?(ExternalFuncDef) then
                return mod.functions[node.name] if mod.functions[node.name]
                func = mod.functions.add(node.name, llvm_arg_types, node.return_type.llvm_type)
                @function_pointers[node] = func

                return func
            end

            old_pos = builder.insert_block

            func = mod.functions.add(node.ir_name, llvm_arg_types, node.return_type.llvm_type)
            func.linkage = :internal # Allow llvm to optimize this function away
            @function_pointers[node] = func

            entry = func.basic_blocks.append "entry"
            builder.position_at_end entry

            with_new_scope(false) do
                args.each_with_index do |arg, i|
                    func.params[i].name = arg.name
                    if i == 0 && node.owner_type && node.owner_type.pass_as_this? then
                        @variable_pointers["this"] = func.params[i]
                    else
                        ptr = builder.alloca arg.type.llvm_type, arg.name
                        @variable_pointers[arg.name] = ptr
                        builder.store func.params[i], ptr
                    end
                end

                node.body.accept self
            end

            builder.ret nil if node.return_type.is_a?(VoidType) and not node.body.returns?
            builder.position_at_end old_pos

            # Generate overriding functions because they might be virtually invoked.
            node.overriding_functions.each do |type, func|
                generate_function(func) unless @function_pointers[func]
            end

            func
        end

        def visit_if(node)
            the_func = builder.insert_block.parent

            then_block = the_func.basic_blocks.append "if.then"
            else_block = the_func.basic_blocks.append "if.else" if node.else_body
            merge_block = the_func.basic_blocks.append "if.after" unless node.returns?

            cond = node.condition.accept(self)
            node.else_body ? builder.cond(cond, then_block, else_block) : builder.cond(cond, then_block, merge_block)

            builder.position_at_end then_block
            with_new_scope { node.if_body.accept self }
            builder.br merge_block unless node.if_body.returns?

            if node.else_body then
                builder.position_at_end else_block
                with_new_scope { node.else_body.accept self }
                builder.br merge_block unless node.else_body.returns?
            end

            builder.position_at_end merge_block if merge_block
            nil
        end

        def visit_for(node)
            the_func = builder.insert_block.parent

            cond_block = the_func.basic_blocks.append "loop.cond"
            body_block = the_func.basic_blocks.append "loop.body"
            after_block = the_func.basic_blocks.append "loop.after"

            node.init.accept self if node.init
            builder.br cond_block

            builder.position_at_end cond_block
            builder.cond node.cond.accept(self), body_block, after_block

            builder.position_at_end body_block
            with_new_scope { node.body.accept self }
            node.step.accept self if node.step
            builder.br cond_block

            builder.position_at_end after_block
        end

        def visit_is_a(node)
            val = node.target.accept self

            unless mod.functions["is_a"]
                old_pos = builder.insert_block

                func = mod.functions.add("is_a", [program.object.llvm_type, VOID_PTR], LLVM::Int1)
                func.linkage = :internal

                builder.position_at_end func.basic_blocks.append("init")
                once_block = func.basic_blocks.append("once")
                body_block = func.basic_blocks.append("body")
                next_if_block = func.basic_blocks.append("next.if")
                next_advance_block = func.basic_blocks.append("next.advance")
                true_block = func.basic_blocks.append("true")
                false_block = func.basic_blocks.append("false")

                is_obj_null = builder.icmp :ne, func.params[0], builder.int2ptr(LLVM::Int(0), program.object.llvm_type)
                typeinfo_ptr = builder.alloca ObjectType::TYPEINFO
                builder.cond(is_obj_null, once_block, false_block)

                builder.position_at_end once_block
                ptr = builder.gep(func.params[0], [LLVM::Int(0), LLVM::Int(1)])
                builder.store builder.load(builder.load(ptr)), typeinfo_ptr
                builder.br body_block

                builder.position_at_end next_if_block
                parent = builder.load builder.gep(typeinfo_ptr, [LLVM::Int(0), LLVM::Int(0)])
                parent_is_null = builder.icmp :ne, parent, builder.int2ptr(LLVM::Int(0), VOID_PTR)
                builder.cond(parent_is_null, next_advance_block, false_block)

                builder.position_at_end next_advance_block
                builder.store builder.load(builder.bit_cast(parent, ObjectType::TYPEINFO_PTR)), typeinfo_ptr
                builder.br body_block

                builder.position_at_end body_block
                name_ptr = builder.load builder.gep typeinfo_ptr, [LLVM::Int(0), LLVM::Int(1)]
                is_eq = builder.icmp :eq, name_ptr, func.params[1]
                builder.cond(is_eq, true_block, next_if_block)

                builder.position_at_end true_block
                builder.ret LLVM::TRUE

                builder.position_at_end false_block
                builder.ret LLVM::FALSE

                builder.position_at_end old_pos
            end

            typeinfo = get_or_create_type_info(node.comp_type)
            builder.call mod.functions["is_a"], builder.bit_cast(val, program.object.llvm_type), builder.load(builder.gep(typeinfo, [LLVM::Int(0), LLVM::Int(1)]))
        end

        private
        def with_new_scope(inherit = true)
            old, @variable_pointers = @variable_pointers, inherit ? ParentHash.new(@variable_pointers) : {}
            yield
            @variable_pointers = old
        end

        def member_to_ptr(node)
            ptr_to_obj = node.object.accept(self)
            index = node.object.type.var_index node.field.value

            generate_null_check(node, node.object.type, ptr_to_obj)
            builder.gep ptr_to_obj, [LLVM::Int(0), LLVM::Int(index)], node.field.value + "_ptr"
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
            @type_infos[type] = add_global("typeinfo.#{type.full_name}", LLVM::ConstantStruct.const([parent_ptr, builder.global_string_pointer(type.full_name)]))
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

        def allocate_string(val_ptr)
            unless mod.functions["__do_allocate_string"]
                old_pos = builder.insert_block

                func = mod.functions.add("__do_allocate_string", [VOID_PTR], program.string.llvm_type)
                func.linkage = :internal
                builder.position_at_end func.basic_blocks.append("entry")

                allocated_struct = builder.malloc program.string.llvm_struct, "String"
                memset allocated_struct, LLVM::Int(0), program.string.llvm_struct.size
                populate_vtable allocated_struct, program.string

                builder.store func.params[0], builder.struct_gep(allocated_struct, 2)
                builder.ret allocated_struct

                builder.position_at_end old_pos
            end

            builder.call mod.functions["__do_allocate_string"], val_ptr
        end

        def generate_null_check(node, val_type, val)
            return unless val_type.is_a?(ObjectType) || val_type.is_a?(StructType) || val_type.is_a?(PointerType) || val_type.is_a?(FunctionType)

            puts_fun = mod.functions["puts"] || mod.functions.add("puts", [VOID_PTR], LLVM::Int)
            exit_fun = mod.functions["exit"] || mod.functions.add("exit", [LLVM::Int], LLVM.Void)

            the_func = builder.insert_block.parent

            fail_block = the_func.basic_blocks.append "null_chk.#{node.object_id}.fail"
            next_block = the_func.basic_blocks.append "null_chk.#{node.object_id}.after"

            is_null = builder.icmp :eq, builder.ptr2int(val, LLVM::Int), LLVM::Int(0)
            builder.cond(is_null, fail_block, next_block)

            builder.position_at_end fail_block
            err_msg = "#{node.filename}##{node.line}: ERROR: Tried to manipulate or read null"
            builder.call puts_fun, builder.global_string_pointer(err_msg)
            builder.call exit_fun, LLVM::Int(1)
            builder.br next_block

            builder.position_at_end next_block
        end
    end

    class Function
        def ir_name
            if owner_type then
                "#{owner_type.name}##{name}<#{args.map(&:type).map(&:name).join ","}>"
            else
                "#{name}<#{args.map(&:type).map(&:name).join ","}>"
            end
        end
    end
end
