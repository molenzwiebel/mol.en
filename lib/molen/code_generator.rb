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
        visitor = GeneratingVisitor.new mod, return_type
        Body.from(contents).accept visitor
        visitor.end_func

        visitor.llvm_mod.dump if dump_ir
        visitor.llvm_mod
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
            builder.ret @last
        end

        def enter_scope
            @scope = Scope.new @scope
        end

        def leave_scope
            @scope = @scope.parent
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

        def visit_arg(node)
            node.type = mod[node.type.name]
        end

        def visit_function(node)
            old_pos = builder.insert_block

            node.args.each {|x| x.accept self}

            arg_types = node.args.map(&:type).map(&:llvm_type)
            ret_type = mod[node.ret_type.name]
            func = llvm_mod.functions.add(node.name, arg_types, ret_type.llvm_type)
            func.linkage = :internal # Allow llvm to optimize this function away
            entry = func.basic_blocks.append "entry"
            builder.position_at_end entry

            old_scope = @scope

            @scope = Scope.new # We don't want functions talking to our variables because they won't exist.
            node.args.each_with_index do |arg, i|
                ptr = @builder.alloca(arg.type.llvm_type, arg.name)
                @scope.define(arg.name, { ptr: ptr, type: arg.type })
                @builder.store func.params[i], ptr
            end

            node.body.accept self
            builder.ret ret_type == mod["void"] ? nil : @last
            builder.position_at_end old_pos
            @scope = old_scope

            false
        end
    end
end