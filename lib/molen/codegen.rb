require 'llvm/execution_engine'

module Molen
    def run(src, filename = "unknown_file")
        Molen.run(src, filename)
    end

    def self.run(src, filename = "unknown_file")
        mod = generate(src, filename)
        LLVM.init_jit
        engine = LLVM::JITCompiler.new mod
        engine.run_function mod.functions["molen_main"]
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
        attr_accessor :mod, :llvm_mod, :builder

        def initialize(mod, ret_type)
            @mod = mod

            @llvm_mod = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = llvm_mod.functions.add "molen_main", [], ret_type ? ret_type.llvm_type : LLVM.Void
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            llvm_mod.functions.add("main", [], LLVM::Int32) do |f|
                f.basic_blocks.append.build do |b|
                    b.call llvm_mod.functions["molen_main"]
                    b.ret LLVM::Int(0)
                end
            end

            @vtables = {}

            @variable_pointers = Scope.new
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
            builder.global_string_pointer node.value
        end

        def visit_identifier(node)
            builder.load @variable_pointers[node.value], node.value
        end

        def visit_body(node)
            node.contents.each {|n| n.accept self}
        end

        def visit_native_body(node)
            instance_exec *builder.insert_block.parent.params.to_a, &node.block
        end

        def visit_member_access(node)
            builder.load member_to_ptr(node), node.field.value
        end

        def visit_instance_variable(node)
            obj_ptr = builder.load @variable_pointers["this"]
            index = node.owner.instance_var_index node.value
            builder.load builder.gep(obj_ptr, [LLVM::Int(0), LLVM::Int(index)], node.value + "_ptr"), node.value
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
            else
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                obj_ptr = builder.load @variable_pointers["this"]
                index = node.name.owner.instance_var_index node.name.value
                builder.store val, builder.gep(obj_ptr, [LLVM::Int(0), LLVM::Int(index)], node.name.value + "_ptr")
            end
        end

        def visit_return(node)
            builder.ret node.value ? node.value.accept(self) : nil
        end

        def visit_new(node)
            allocated_struct = builder.malloc node.type.llvm_struct, node.type.name
            populate_vtable allocated_struct, node.type

            if node.target_constructor then
                create_func = @function_pointers[node.target_constructor]
                create_func = generate_function(node.target_constructor) unless create_func
                casted_this = builder.bit_cast allocated_struct, node.target_constructor.owner.type.llvm_type

                args = [casted_this]
                node.args.each do |arg|
                    args << arg.accept(self)
                end

                builder.call create_func, *args
            end

            allocated_struct
        end

        def visit_call(node)
            func = @function_pointers[node.target_function]
            unless func
                func = generate_function(node.target_function)
            end

            # Setup arguments and cast them if needed.
            args = []
            node.args.each_with_index do |arg, i|
                val = arg.accept(self)
                if arg.type != node.target_function.args[i].type then
                    val = builder.bit_cast val, node.target_function.args[i].type.llvm_type
                end
                args << val
            end

            if node.object then
                obj = node.object.accept(self)
                casted_this = builder.bit_cast obj, node.target_function.owner.type.llvm_type
                args = [casted_this] + args
            end

            ret_ptr = builder.call func, *args
            return ret_ptr if func.function_type.return_type != LLVM.Void
            return nil
        end

        # This is not a normal visit_### function because we only
        # generate functions that are actually called. Performance :)
        def generate_function(node)
            # Save the old position of the builder to return to it at the end
            old_pos = builder.insert_block

            # Add a 'this' argument at the start if this is an instance method
            args = node.args
            args = [FunctionArg.new("this", node.owner.type)] + args if node.owner

            # Compute types and create the actual LLVM function
            ret_type = node.return_type ? node.return_type.llvm_type : LLVM.Void
            llvm_arg_types = args.map(&:type).map(&:llvm_type)

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

        def member_to_ptr(node)
            ptr_to_obj = node.object.accept(self)
            index = node.object.type.instance_var_index node.field.value

            return builder.gep ptr_to_obj, [LLVM::Int(0), LLVM::Int(index)], node.field.value + "_ptr"
        end

        def get_or_create_vtable(type)
            return @vtables[type.name] if @vtables[type.name]

            parent_ptr = type.superclass ? get_or_create_vtable(type.superclass) : builder.int2ptr(LLVM::Int(0), LLVM::Pointer(type.vtable_type))

            const = LLVM::ConstantStruct.const([parent_ptr, builder.global_string_pointer(type.name)])

            global = @vtables[type.name] = llvm_mod.globals.add(const, "#{type.name}_vtable") do |var|
                var.linkage = :private
                var.global_constant = true
                var.initializer = const
            end
        end

        def populate_vtable(allocated_struct, type)
            str = builder.struct_gep allocated_struct, 0
            vtable = get_or_create_vtable(type).bitcast_to LLVM::Pointer(type.vtable_type)
            builder.store vtable, str
        end
    end

    class Function
        def ir_name
            if owner then
                "#{owner.type.name}__#{name}<#{args.map(&:type).map(&:name).join ","}>"
            else
                "#{name}<#{args.map(&:type).map(&:name).join ","}>"
            end
        end
    end
end
