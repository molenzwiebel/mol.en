require 'llvm/core'
require 'llvm/execution_engine'

module Molen
    def run(code, return_type = "Int", dump_ir = true)
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

            main_func = llvm_mod.functions.add("main", [], mod[ret_type].llvm_type)
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            @strings = {}
            @scope = Scope.new
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
            return false if node.op != "=" # TODO

            node.right.accept self
            builder.store get_last, @scope[node.left.value][:ptr]
            false
        end

        def visit_function(node)
            old_pos = builder.insert_block
            llvm_arg_types = node.args.map(&:type).map(&:llvm_type)

            func = llvm_mod.functions.add(node.name, llvm_arg_types, node.ret_type.llvm_type)
            func.linkage = :internal # Allow llvm to optimize this function away
            entry = func.basic_blocks.append "entry"
            builder.position_at_end entry

            with_new_scope(false) do
                node.args.each_with_index do |arg, i|
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
    end
end