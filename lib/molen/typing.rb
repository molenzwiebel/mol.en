
# This class is responsible for "typing" nodes. This means that we assign
# types to the nodes so code generation does not have to figure out what
# function to call with what arguments. This class for example figures out
# that after `var x = 10`, x has the type Int. The typing visitor is also
# responsible for validating function calls and assignments so that only job
# of the codegen is to generate code.
module Molen
    class ASTNode
        attr_accessor :type
    end

    class Call
        # The target of this call. This is the actual "Function" 
        # instance and makes generating of the call a whole lot easier.
        attr_accessor :target
    end

    class TypingVisitor < Visitor
        attr_accessor :mod

        def initialize(mod)
            @mod = mod

            @scope = Scope.new
            @classes = {}
            @functions = {}
        end

        def visit_int(node)
            node.type = mod["Int"]
        end

        def visit_double(node)
            node.type = mod["Double"]
        end

        def visit_bool(node)
            node.type = mod["Bool"]
        end

        def visit_str(node)
            node.type = mod["String"]
        end

        def end_visit_body(node)
            node.type = node.nodes.last.type
        end

        def visit_var(node)
            node.type = @scope[node.value]
        end

        def visit_function(node)
            clazz = node.class
            if clazz
                @classes[clazz.name][:defs][node.name] = node
            else
                @functions[node.name] = node
            end
            false
        end

        def visit_binary(node)
            return false if node.op != "=" # TODO
            node.right.accept self # Check value.

            old_type = @scope[node.left.value]
            raise "Undefined variable '#{node.left.value}'" unless old_type

            node.type = node.left.type = node.right.type
            raise "Cannot assign #{node.type.name} to '#{node.left.value}' (a #{old_type.name})" if old_type != node.type
            false
        end

        def visit_vardef(node)
            node.value.accept self if node.value
            defined_type = mod[node.type.name] if node.type
            raise "Conflicting types: var statement specified type #{defined_type.name} while being assigned value of type #{node.value.type.name}" if defined_type and node.value and defined_type != node.type

            node.type = defined_type || node.value.type
            raise "Vardef has no type?" unless node.type

            @scope.define node.name.value, node.type
            false
        end

        def visit_classdef(node)
            @classes[node.name] ||= {defs: {}}
        end

        private
        def with_new_scope(inherit = true)
            old_scope = @scope
            if inherit then
                @scope = Scope.new old_scope
            else
                @scope = Scope.new
            end
            yield
            @scope = old_scope
        end
    end
end