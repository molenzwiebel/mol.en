
module Molen
    class ASTNode
        attr_accessor :type
    end

    def dump_ir(code)
        parser = create_parser code
        contents = []
        until (n = parser.parse_node).nil?
            contents << n
        end

        mod = Module.new
        visitor = GeneratingVisitor.new mod
        Body.from(contents).accept visitor
        visitor.end_func

        visitor.llvm_mod.dump
    end

    class GeneratingVisitor < Visitor
        attr_accessor :mod, :llvm_mod, :builder

        def initialize(mod)
            @mod = mod

            @llvm_mod = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = llvm_mod.functions.add("main", [], LLVM::Int)
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            @strings = {}
            @scope = Scope.new
        end

        def end_func
            builder.ret @last
        end

        def visit_int(node)
            node.type = mod["Int"]
            @last = LLVM::Int32.from_i node.value
        end

        def visit_double(node)
            node.type = mod["Double"]
            @last = LLVM::Double node.value
        end

        def visit_bool(node)
            node.type = mod["Bool"]
            @last = node.value ? LLVM::TRUE : LLVM::FALSE
        end

        def visit_str(node)
            node.type = mod["String"]
            @last = @strings[node.value] || @strings[node.value] = builder.global_string_pointer(node.value)
        end

        def visit_binary(node)
            return false if node.op != "=" # TODO

            node.right.accept self
            node.type = node.left.type = node.right.type
            var = @scope[node.left.value]
            raise "Undefined variable '#{node.left.value}'" unless var
            raise "Cannot assign #{node.type.name} to '#{node.left.value}' (#{var[:type].name})" if var[:type] != node.type
            @builder.store @last, var[:ptr]

            false
        end

        def visit_var(node)
            var = @scope[node.value]
            raise "Undefined variable '#{node.value}'" unless var
            node.type = var[:type]
            @last = builder.load var[:ptr], node.value
        end

        def visit_vardef(node)
            node.value.accept self if node.value
            node.type = mod[node.type.name] if node.type
            raise "Conflicting types: var statement specified type #{node.type.name} while being assigned value of type #{node.value.type.name}" if node.type and node.value and @last and node.value.type != node.type
        
            type = node.type || node.value.type
            raise "Vardef has no type?" unless type

            var = @scope.define(node.name.value, {
                ptr: builder.alloca(type.llvm_type, node.name.value),
                type: type
            })
            @builder.store @last, var[:ptr] if node.value and @last

            false
        end
    end
end