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

        def visit_member_access(node)
            builder.load member_to_ptr(node), node.field.value
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
            else
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                builder.store val, member_to_ptr(node.name)
                return val
            end
        end

        def visit_return(node)
            builder.ret node.value ? node.value.accept(self) : nil
        end

        def visit_new(node)
            allocated_struct = builder.malloc node.type.llvm_struct, node.type.name

            if node.target_constructor then
                create_func = @functions[node.target_constructor.ir_name]
                create_func = generate_function(node.target_constructor) unless create_func
                casted_this = builder.bit_cast allocated_struct, node.target_constructor.object.type.llvm_type

                args = [casted_this]
                node.args.each do |arg|
                    args << arg.accept(self)
                end

                builder.call create_func, *args
            end

            allocated_struct
        end

        def visit_call(node)
            func = @function_pointers[node.target_function.ir_name]
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
            @function_pointers[node.ir_name] = func

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
