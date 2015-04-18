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

    def run(code, return_type = "Int", dump_ir = true)
        mod = gen(code, return_type, dump_ir)
        LLVM.init_jit

        engine = LLVM::JITCompiler.new(mod)
        engine.run_function mod.functions["molen_main"]
    end

    def gen(code, return_type = "Int", dump_ir = true)
        parser = create_parser code
        contents = []
        until (n = parser.parse_node).nil?
            contents << n
        end

        mod = Module.new
        type_visitor = TypingVisitor.new mod
        gen_visitor = GeneratingVisitor.new mod, return_type

        body = Body.from(contents)
        body.accept type_visitor
        body.accept gen_visitor

        gen_visitor.end_func

        gen_visitor.llvm_mod.verify
        gen_visitor.llvm_mod.dump if dump_ir
        gen_visitor.llvm_mod
    end

    class GeneratingVisitor < Visitor
        attr_accessor :mod, :llvm_mod, :builder

        def initialize(mod, ret_type)
            @mod = mod

            @llvm_mod = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = llvm_mod.functions.add("molen_main", [], mod[ret_type].llvm_type)
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            @strings = {}
            @scope = Scope.new
            @functions = {}
        end

        def end_func
            builder.ret get_last
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

        def visit_vardef(node)
            node.value.accept self
            var = @scope.define(node.name.value, {
                ptr: builder.alloca(node.type.llvm_type, node.name.value),
                type: node.type
            })
            builder.store get_last, var[:ptr] if node.value and @last

            false
        end

        def visit_binary(node)
            if node.op == "+" then
                load_and_convert_two_numerics node.left, node.right do |is_d, left, right|
                    @last = is_d ? builder.fadd(left, right) : builder.add(left, right)
                end
            elsif node.op == "-" then
                load_and_convert_two_numerics node.left, node.right do |is_d, left, right|
                    @last = is_d ? builder.fsub(left, right) : builder.sub(left, right)
                end
            elsif node.op == "*" then
                load_and_convert_two_numerics node.left, node.right do |is_d, left, right|
                    @last = is_d ? builder.fmul(left, right) : builder.mul(left, right)
                end
            elsif node.op == "/" then
                load_and_convert_two_numerics node.left, node.right do |is_d, left, right|
                    @last = is_d ? builder.fdiv(left, right) : builder.sdiv(left, right)
                end
            elsif node.op == "<" or node.op == "<=" then
                mode = node.op == "<" ? :ult : :ule
                load_and_convert_two_numerics node.left, node.right do |is_d, left, right|
                    @last = is_d ? builder.fcmp(mode, left, right) : builder.icmp(mode, left, right)
                end
            elsif node.op == ">" or node.op == ">=" then
                mode = node.op == ">" ? :ugt : :uge
                load_and_convert_two_numerics node.left, node.right do |is_d, left, right|
                    @last = is_d ? builder.fcmp(mode, left, right) : builder.icmp(mode, left, right)
                end
            elsif node.op == "&&" or node.op == "and" then
                load_two_values node.left, node.right do |left, right|
                    @last = builder.and left, right
                end
            elsif node.op == "||" or node.op == "or" then
                load_two_values node.left, node.right do |left, right|
                    @last = builder.or left, right
                end
            else
                return false if node.op != "=" # TODO

                node.right.accept self
                builder.store get_last, @scope[node.left.value][:ptr]
            end
            false
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
                args = [get_last] + args
            end

            @last = builder.call func, *args
            false
        end

        def visit_function(node)
            old_pos = builder.insert_block
            args = node.args
            args = [Arg.new("this", node.parent.type)] + args if node.parent.is_a? ClassDef
            llvm_arg_types = args.map(&:type).map(&:llvm_type)

            func = llvm_mod.functions.add(node.name, llvm_arg_types, node.ret_type.llvm_type)
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

            builder.ret get_last
            builder.position_at_end old_pos

            false
        end

        def visit_classdef(node)
            node.funcs.each {|f| f.accept self}
            false
        end

        private
        def get_last
            last = @last
            @last = nil
            last
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

            is_double = left.type == mod["Double"] or right.type == mod["Double"]
            if is_double then
                left_val = builder.si2fp left_val, LLVM::Double if left.type != mod["Double"]
                right_val = builder.si2fp right_val, LLVM::Double if right.type != mod["Double"]
            end

            yield is_double, left_val, right_val
        end
    end
end