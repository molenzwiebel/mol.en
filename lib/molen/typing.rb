
module Molen
    class ASTNode
        attr_accessor :type
    end

    class Call
        attr_accessor :target_function
    end

    class New
        attr_accessor :target_constructor
    end

    class TypingVisitor < Visitor
        attr_accessor :mod

        def initialize(mod)
            @mod = mod

            @scope = Scope.new
            @functions = Scope.new
        end

        def visit_int(node)
            node.type = mod["Int"]
        end

        def visit_bool(node)
            node.type = mod["Bool"]
        end

        def visit_double(node)
            node.type = mod["Double"]
        end

        def visit_str(node)
            node.type = mod["String"]
        end

        def visit_identifier(node)
            raise "Undefined variable '#{node.value}'" unless @scope[node.value]
            node.type = @scope[node.value]
        end

        def visit_constant(node)
            raise "Undefined constant '#{node.value}'" unless @scope[node.value]
            node.type = @scope[node.value]
        end

        def visit_if(node)
            node.condition.accept self
            with_new_scope { node.then.accept self }
            with_new_scope { node.else.accept self } if node.else
            raise "Expected condition in if to be a boolean" if node.condition.type != mod["Bool"]
        end

        def visit_for(node)
            node.init.accept self if node.init
            node.cond.accept self
            node.step.accept self if node.step
            with_new_scope { node.body.accept self }
            raise "Expected condition in loop to be a boolean" if node.cond.type != mod["Bool"]
        end

        def visit_member_access(node)
            node.object.accept self
            obj_type = node.object.type
            raise "Cannot access member of primitive type" if obj_type.is_a? PrimitiveType
            raise "Unknown member #{node.field.value} on object of type #{obj_type.name}" unless obj_type.instance_variables[node.child.value]
            node.type = obj_type.instance_variables[node.child.value]
        end

        def visit_body(node)
            node.nodes.each_with_index do |n, index|
                n.accept self
                raise "Unreachable code." if n.is_a?(If) && n.definitely_returns && index != node.nodes.size - 1
            end
            last = node.nodes.last
            node.type = (last and last.is_a?(Return)) ? last.type : nil
        end

        private
        def find_overloaded_method(in_scope, name, args)
            return nil if in_scope[name].nil? || !in_scope[name].is_a?(::Array) || in_scope[name].size == 0

            matches = {}
            in_scope[name].each do |func|
                next if func.args.size != args.size
                callable, dist = func.callabe? args.map(&:type)
                next if not callable
                (matches[dist] ||= []) << func
            end
            return nil if matches.size == 0

            dist, functions = matches.min_by {|k, v| k}
            raise "Multiple functions named #{name} found matching argument set '#{args.map(&:type).map(&:name).join ", "}'. Be more specific!" if functions and functions.size > 1
            functions.first
        end

        def with_new_scope(inherit = true, inherit_from = nil)
            old_scope = @scope
            @scope = inherit ? (Scope.new inherit_from || old_scope) : Scope.new
            yield
            @scope = old_scope
        end
    end
end
