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
        body = parse(src, filename)
        mod = Molen::Module.new
        body.accept TypingVisitor.new(mod)
        visitor = GeneratingVisitor.new(mod, body.type)
        body.accept visitor
        visitor.builder.ret nil
        visitor.llvm_mod
    end

    class GeneratingVisitor < Visitor
        VOID_PTR = LLVM::Pointer(LLVM::Int8)
        attr_accessor :mod, :llvm_mod, :builder

        def initialize(mod, ret_type)
            @mod = mod

            @llvm_mod = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = llvm_mod.functions.add "molen_main", [], ret_type ? ret_type.llvm_type : LLVM.Void
            main_func.linkage = :internal
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            llvm_mod.functions.add("main", [], LLVM::Int32) do |f|
                f.basic_blocks.append.build do |b|
                    b.call llvm_mod.functions["molen_main"]
                    b.ret LLVM::Int(0)
                end
            end

            @type_infos = {}
            @vtables = {}
            @object_allocators = {}

            @variable_pointers = Scope.new
            @function_pointers = {}
        end

        def visit_import(node)
            node.imported_body.accept self
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
            builder.load @variable_pointers[node.value], node.value
        end

        def visit_body(node)
            node.contents.each {|n| n.accept self}
        end

        def visit_size_of(node)
            type = node.size_type.llvm_type
            type = node.size_type.llvm_struct if node.size_type.is_a?(StructType)

            type.is_a?(LLVM::Type) ? type.size : type.type.size
        end

        def visit_native_body(node)
            instance_exec *builder.insert_block.parent.params.to_a, &node.block
        end

        def visit_member_access(node)
            builder.load member_to_ptr(node), node.field.value
        end

        def visit_cast(node)
            builder.bit_cast node.expr.accept(self), node.type.llvm_type
        end

        def visit_null(node)
            builder.int2ptr LLVM::Int(0), VOID_PTR
        end

        def visit_instance_variable(node)
            obj_ptr = builder.load @variable_pointers["this"]
            index = node.owner.instance_var_index node.value
            builder.load builder.gep(obj_ptr, [LLVM::Int(0), LLVM::Int(index)], node.value + "_ptr"), node.value
        end

        def visit_pointer_of(node)
            if node.expr.is_a? InstanceVariable then
                obj_ptr = builder.load @variable_pointers["this"]
                index = node.expr.owner.instance_var_index node.expr.value
                ptr = builder.struct_gep(obj_ptr, index)
            else
                ptr = @variable_pointers[node.expr.value]
            end
            ptr = builder.load(ptr) if node.expr.type.is_a? StructType
            ptr
        end

        def visit_assign(node)
            if node.name.is_a?(Identifier) then
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                unless @variable_pointers[node.name.value]
                    @variable_pointers.define node.name.value, builder.alloca(node.type.llvm_type, node.name.value)
                end
                builder.store val, @variable_pointers[node.name.value]
                return val
            elsif node.name.is_a?(MemberAccess) then
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                builder.store val, member_to_ptr(node.name)
                return val
            elsif node.name.is_a?(InstanceVariable) then
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                obj_ptr = builder.load @variable_pointers["this"]
                index = node.name.owner.instance_var_index node.name.value
                builder.store val, builder.gep(obj_ptr, [LLVM::Int(0), LLVM::Int(index)], node.name.value + "_ptr")
                return val
            end
        end

        def visit_return(node)
            if node.value && node.value.type.nil? then
                builder.ret builder.int2ptr LLVM::Int(0), node.func_ret_type.llvm_type
            else
                builder.ret node.value ? node.value.accept(self) : nil
            end
        end

        def visit_new(node)
            allocator = @object_allocators[node.type.name]
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

        def generate_object_allocator(type)
            old_pos = builder.insert_block

            @object_allocators[type.name] = func = llvm_mod.functions.add("_allocate_#{type.name}", [], type.llvm_type)
            func.linkage = :internal
            builder.position_at_end func.basic_blocks.append("entry")

            allocated_struct = builder.malloc type.llvm_struct, type.name
            memset allocated_struct, LLVM::Int(0), type.llvm_struct.size
            populate_vtable allocated_struct, type if type.is_a?(ObjectType)

            builder.ret allocated_struct

            builder.position_at_end old_pos
            func
        end

        def visit_new_array(node)
            arr_struct = builder.malloc node.type.llvm_struct, node.type.name
            memset arr_struct, LLVM::Int(0), node.type.llvm_struct.size

            # If < 8, cap = 8, else cap = nearest power of 2
            capacity = node.elements.size <= 8 ? 8 : 2 ** Math.log(node.elements.size, 2).ceil

            builder.store LLVM::Int(node.elements.size), builder.struct_gep(arr_struct, 0)
            builder.store LLVM::Int(capacity), builder.struct_gep(arr_struct, 1)

            arr_buffer = builder.array_malloc(node.type.element_type.llvm_type, LLVM::Int(capacity))
            memset arr_buffer, LLVM::Int(0), builder.mul(node.type.element_type.llvm_type.size, LLVM::Int64.from_i(capacity))
            builder.store arr_buffer, builder.struct_gep(arr_struct, 2)

            node.elements.each_with_index do |elem, index|
                val = elem.accept(self)
                val = builder.bit_cast val, node.type.element_type.llvm_type if node.type.element_type != elem.type
                builder.store val, builder.gep(arr_buffer, [LLVM::Int(index)])
            end

            arr_struct
        end

        def visit_call(node)
            # Setup arguments and cast them if needed.
            args = []
            node.args.each_with_index do |arg, i|
                val = arg.accept(self)
                if arg.type != node.target_function.args[i].type then
                    val = builder.bit_cast val, node.target_function.args[i].type.llvm_type
                end
                args << val
            end

            if node.object && !node.object.is_a?(Constant) then
                obj = node.object.accept(self)
                casted_this = builder.bit_cast obj, node.target_function.owner_type.llvm_type
                args = [casted_this] + args
            end

            if node.object && node.object.type.is_a?(ObjectType) && node.target_function.overriding_functions.size > 0 then
                func = @function_pointers[node.target_function]

                vtable_ptr = builder.bit_cast args[0], LLVM::Pointer(LLVM::Pointer(LLVM::Pointer(func.function_type)))
                vtable = builder.load vtable_ptr, "vtable"

                func_ptr = builder.inbounds_gep(vtable, [LLVM::Int64.from_i(node.object.type.function_index(node.target_function))])
                loaded_func = builder.load func_ptr

                res = builder.call loaded_func, *args
                return res if func.function_type.return_type != LLVM.Void
                return nil
            else
                func = @function_pointers[node.target_function]
                unless func
                    func = generate_function(node.target_function)
                end

                ret_ptr = builder.call func, *args
                return ret_ptr if func.function_type.return_type != LLVM.Void
                return nil
            end
        end

        # This is not a normal visit_### function because we only
        # generate functions that are actually called. Performance :)
        def generate_function(node)
            # Add a 'this' argument at the start if this is an instance method
            args = node.args
            args = [FunctionArg.new("this", node.owner_type)] + args if node.owner.is_a?(ClassDef) && node.owner_type

            # Compute types and create the actual LLVM function
            ret_type = node.return_type ? node.return_type.llvm_type : LLVM.Void
            llvm_arg_types = args.map(&:type).map(&:llvm_type)

            if node.is_a?(ExternalFunc) then
                func = llvm_mod.functions.add(node.name, llvm_arg_types, ret_type)
                @function_pointers[node] = func

                return func
            end

            # Save the old position of the builder to return to it at the end
            old_pos = builder.insert_block

            func = llvm_mod.functions.add(node.ir_name, llvm_arg_types, ret_type)
            func.linkage = :internal # Allow llvm to optimize this function away
            @function_pointers[node] = func

            # Create a new block at jump to it
            entry = func.basic_blocks.append "entry"
            builder.position_at_end entry

            with_new_variable_scope(false) do
                # Save each variable to a fresh pointer so you can change function arguments
                args.each_with_index do |arg, i|
                    ptr = builder.alloca arg.type.llvm_type, arg.name
                    @variable_pointers.define arg.name, ptr
                    builder.store func.params[i], ptr
                end

                node.body.accept self
            end

            builder.ret nil if node.return_type.nil? and not node.body.definitely_returns?
            builder.position_at_end old_pos

            node.overriding_functions.each do |type, func|
                generate_function(func) unless @function_pointers[func]
            end

            func
        end

        def visit_if(node)
            the_func = builder.insert_block.parent

            then_block = the_func.basic_blocks.append "then"
            else_block = the_func.basic_blocks.append "else" if node.else
            merge_block = the_func.basic_blocks.append "merge" unless node.definitely_returns?

            cond = node.condition.accept(self)
            node.else ? builder.cond(cond, then_block, else_block) : builder.cond(cond, then_block, merge_block)

            builder.position_at_end then_block
            with_new_variable_scope { node.then.accept self }
            builder.br merge_block unless node.then.definitely_returns?

            if node.else then
                builder.position_at_end else_block
                with_new_variable_scope { node.else.accept self }
                builder.br merge_block unless node.else.definitely_returns?
            end

            builder.position_at_end merge_block if merge_block
            nil
        end

        def visit_for(node)
            the_func = builder.insert_block.parent

            cond_block = the_func.basic_blocks.append "loop_cond"
            body_block = the_func.basic_blocks.append "loop_body"
            after_block = the_func.basic_blocks.append "after_loop"

            node.init.accept self if node.init
            builder.br cond_block

            builder.position_at_end cond_block
            builder.cond node.cond.accept(self), body_block, after_block

            builder.position_at_end body_block
            with_new_variable_scope { node.body.accept self }
            node.step.accept self if node.step
            builder.br cond_block

            builder.position_at_end after_block
        end

        private
        def with_new_variable_scope(inherit = true)
            old_var_scope = @variable_pointers

            @variable_pointers = inherit ? Scope.new(@variable_pointers) : Scope.new
            yield
            @variable_pointers = old_var_scope
        end

        def memset(pointer, value, size)
            memset_func = llvm_mod.functions['memset'] || llvm_mod.functions.add('memset', [VOID_PTR, LLVM::Int, LLVM::Int], VOID_PTR)

            pointer = builder.bit_cast pointer, VOID_PTR
            builder.call memset_func, pointer, value, builder.trunc(size, LLVM::Int32)
        end

        def member_to_ptr(node)
            ptr_to_obj = node.object.accept(self)
            index = node.object.type.instance_var_index node.field.value

            return builder.gep ptr_to_obj, [LLVM::Int(0), LLVM::Int(index)], node.field.value + "_ptr"
        end

        def get_or_create_type_info(type)
            return @type_infos[type.name] if @type_infos[type.name]

            parent_ptr = type.superclass ? builder.bit_cast(get_or_create_type_info(type.superclass), VOID_PTR) : builder.int2ptr(LLVM::Int(0), VOID_PTR)
            @type_infos[type.name] = add_global("typeinfo.#{type.name}", LLVM::ConstantStruct.const([parent_ptr, builder.global_string_pointer(type.name)]))
        end

        def get_or_create_vtable(type)
            return @vtables[type.name] if @vtables[type.name]

            used_funcs = type.vtable_functions.map do |f|
                generate_function(f) unless @function_pointers[f]
                builder.bit_cast(@function_pointers[f], VOID_PTR)
            end

            @vtables[type.name] = add_global("vtable.#{type.name}", LLVM::ConstantArray.const(VOID_PTR, used_funcs))
        end

        def populate_vtable(allocated_struct, type)
            builder.store get_or_create_vtable(type).bitcast_to(ObjectType::VTABLE_PTR), builder.struct_gep(allocated_struct, 0)
            builder.store get_or_create_type_info(type).bitcast_to(ObjectType::TYPEINFO_PTR), builder.struct_gep(allocated_struct, 1)
        end

        def allocate_string(val_ptr)
            allocated_struct = builder.malloc mod["String"].llvm_struct, "String"
            populate_vtable allocated_struct, mod["String"]
            builder.store val_ptr, builder.struct_gep(allocated_struct, 2)
            allocated_struct
        end

        def add_global(name, val)
            llvm_mod.globals.add(val, name) do |var|
                var.linkage = :private
                var.global_constant = true
                var.initializer = val
            end
        end
    end

    class Function
        def ir_name
            if owner && owner_type then
                "#{owner_type.name}##{name}<#{args.map(&:type).map(&:name).join ","}>"
            else
                "#{name}<#{args.map(&:type).map(&:name).join ","}>"
            end
        end
    end
end
