require 'llvm/core'
require 'llvm/execution_engine'

module Molen
    class Function
        def ir_name
            if parent.is_a? ClassDef
                "#{parent.name}__#{name}"
            else
                "#{name}"
            end
        end
    end

    def run(code, dump_ir = true, verify = true)
        mod = gen(code, dump_ir, verify)
        LLVM.init_jit

        engine = LLVM::JITCompiler.new(mod)
        engine.run_function mod.functions["molen_main"]
    end

    def gen(code, dump_ir = true, verify = true)
        parser = create_parser code
        contents = []
        until (n = parser.parse_node).nil?
            contents << n
        end

        mod = Module.new
        type_visitor = TypingVisitor.new mod

        body = Body.from contents, true
        body.accept type_visitor

        gen_visitor = GeneratingVisitor.new mod, body.type
        body.accept gen_visitor

        gen_visitor.end_main_func unless body.definitely_returns

        gen_visitor.llvm_mod.verify if verify
        gen_visitor.llvm_mod.dump if dump_ir
        gen_visitor.llvm_mod
    end

    class GeneratingVisitor < Visitor
        attr_accessor :mod, :llvm_mod, :builder

        def initialize(mod, ret_type)
            @mod = mod

            @llvm_mod = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = llvm_mod.functions.add("molen_main", [], ret_type ? ret_type.llvm_type : LLVM.Void)
            main_func.linkage = :internal
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            llvm_mod.functions.add("main", [], LLVM::Int32) do |f|
                f.basic_blocks.append.build do |b|
                    b.call llvm_mod.functions["molen_main"]
                    b.ret LLVM::Int(0)
                end
            end

            @strings = {}
            @scope = Scope.new
            @functions = {}
            @functions["putchar"] = llvm_mod.functions.add("putchar", [LLVM::Int], LLVM::Int)
            @functions["puts"] = llvm_mod.functions.add("puts", [LLVM::Pointer(LLVM::Int8)], LLVM::Int)
        end

        def end_main_func
            last = get_last
            builder.ret last
        end

        def visit_int(node)
            @last = LLVM::Int32.from_i node.value
        end

        def visit_double(node)
            @last = LLVM::Double node.value
        end

        def visit_bool(node)
            @last = node.value ? LLVM::TRUE : LLVM::FALSE
        end

        def visit_str(node)
            @last = @strings[node.value] || @strings[node.value] = builder.global_string_pointer(node.value)
        end

        def visit_var(node)
            var = @scope[node.value]
            @last = builder.load var[:ptr], node.value
        end

        def visit_member(node)
            @last = builder.load member_to_ptr(node), node.child.value
        end

        def visit_body(node)
            node.nodes.each {|n| n.accept self}
        end

        def visit_new(node)
            allocated_struct = builder.malloc node.type.llvm_struct, node.type.name

            if node.type.functions["create"] then
                create_func = @functions[node.type.functions["create"].ir_name]
                casted_this = builder.bit_cast allocated_struct, node.type.functions["create"].this_type.llvm_type
                
                args = [casted_this]
                node.args.each do |arg|
                    arg.accept self
                    args << get_last
                end

                builder.call create_func, *args
            end

            @last = allocated_struct
        end

        def visit_vardef(node)
            node.value.accept self
            var = @scope.define(node.name.value, {
                ptr: builder.alloca(node.type.llvm_type, node.name.value),
                type: node.type
            })
            builder.store get_last, var[:ptr] if node.value and @last
        end

        def visit_assign(node)
            if node.name.is_a? Var then
                node.value.accept self
                val = get_last
                builder.store val, @scope[node.name.value][:ptr]
                @last = val
            else
                node.value.accept self
                val = get_last
                builder.store val, member_to_ptr(node.name)
                @last = val
            end
        end

        def visit_call(node)
            func = @functions[node.target.ir_name]

            args = []
            node.args.each do |arg|
                arg.accept self
                args << get_last
            end
            if node.on then
                node.on.accept self
                casted_this = builder.bit_cast get_last, node.target.this_type.llvm_type
                args = [casted_this] + args
            end

            puts "Calling #{node.target.ir_name} with args: #{node.args.map(&:type).map(&:name).join ", "}"
            ret_ptr = builder.call func, *args
            @last = ret_ptr if func.function_type.return_type != LLVM.Void
            puts "Done"
        end

        def visit_if(node)
            node.cond.accept self
            the_func = builder.insert_block.parent

            then_block = the_func.basic_blocks.append "then"
            else_block = the_func.basic_blocks.append "else" if node.else
            merge_block = the_func.basic_blocks.append "merge" unless node.definitely_returns

            node.else ? builder.cond(get_last, then_block, else_block) : builder.cond(get_last, then_block, merge_block)

            builder.position_at_end then_block
            with_new_scope { node.then.accept self }
            builder.br merge_block unless node.then.definitely_returns

            if node.else then
                builder.position_at_end else_block
                with_new_scope { node.else.accept self }
                builder.br merge_block unless node.else.definitely_returns
            end

            builder.position_at_end merge_block if merge_block
        end

        def visit_function(node)
            old_pos = builder.insert_block
            args = node.args
            args = [Arg.new("this", node.this_type)] + args if node.parent.is_a? ClassDef

            ret_type = node.ret_type ? node.ret_type.llvm_type : LLVM.Void
            llvm_arg_types = args.map(&:type).map(&:llvm_type)

            func = llvm_mod.functions.add(node.ir_name, llvm_arg_types, ret_type)
            func.linkage = :internal # Allow llvm to optimize this function away
            @functions[node.ir_name] = func

            entry = func.basic_blocks.append "entry"
            builder.position_at_end entry

            with_new_scope(false) do
                args.each_with_index do |arg, i|
                    ptr = builder.alloca arg.type.llvm_type, arg.name
                    @scope.define(arg.name, { ptr: ptr, type: arg.type })
                    builder.store func.params[i], ptr
                end

                node.body.accept self
            end

            get_last # Just to clear @last
            builder.ret nil if node.ret_type.nil? and not node.body.definitely_returns
            builder.position_at_end old_pos
        end

        def visit_for(node)
            the_func = builder.insert_block.parent

            cond_block = the_func.basic_blocks.append "loop_cond"
            body_block = the_func.basic_blocks.append "loop_body"
            after_block = the_func.basic_blocks.append "after_loop"

            node.init.accept self if node.init
            builder.br cond_block

            builder.position_at_end cond_block
            node.cond.accept self
            builder.cond get_last, body_block, after_block

            builder.position_at_end body_block
            with_new_scope { node.body.accept self }
            node.step.accept self if node.step
            builder.br cond_block

            builder.position_at_end after_block
        end

        def visit_return(node)
            node.value.accept self if node.value
            builder.ret get_last
        end

        def visit_classdef(node)
            node.funcs.each {|f| f.accept self}
        end

        private
        def get_last
            last = @last
            @last = nil
            last
        end

        def member_to_ptr(node)
            node.on.accept self
            ptr_to_obj = get_last
            index = node.on.type.vars.keys.index node.child.value

            return builder.gep ptr_to_obj, [LLVM::Int(0), LLVM::Int(index)], node.child.value + "_ptr"
        end

        def with_new_scope(inherit = true)
            old_scope = @scope

            @scope = inherit ? Scope.new(@scope) : Scope.new
            yield
            @scope = old_scope
        end

        def load_two_values(left, right)
            left.accept self
            left_val = get_last
            right.accept self
            right_val = get_last

            yield left_val, right_val
        end

        def load_and_convert_two_numerics(left, right)
            left.accept self
            left_val = get_last
            right.accept self
            right_val = get_last

            is_double = left.type == mod["double"] || right.type == mod["double"]
            if is_double then
                left_val = builder.si2fp left_val, LLVM::Double if left.type != mod["double"]
                right_val = builder.si2fp right_val, LLVM::Double if right.type != mod["double"]
            end

            yield is_double, left_val, right_val
        end
    end
end