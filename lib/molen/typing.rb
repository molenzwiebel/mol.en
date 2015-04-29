
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

        # Types an int node. Simply assigns the type to be Int
        def visit_int(node)
            node.type = mod["Int"]
        end

        # Types a bool node. Simply assigns the type to be Bool
        def visit_bool(node)
            node.type = mod["Bool"]
        end

        # Types a double node. Simply assigns the type to be Double
        def visit_double(node)
            node.type = mod["Double"]
        end

        # Types an string node. Simply assigns the type to be String
        def visit_str(node)
            node.type = mod["String"]
        end

        # Tries to find the specified identifier in the current scope,
        # and assigns the type of the identifier if found. Errors otherwise
        def visit_identifier(node)
            raise "Undefined variable '#{node.value}'" unless @scope[node.value]
            node.type = @scope[node.value]
        end

        # Tries to find the specified constant in the current scope,
        # and assigns the type of the constant if found. Errors otherwise
        def visit_constant(node)
            raise "Undefined constant '#{node.value}'" unless @scope[node.value]
            node.type = @scope[node.value]
        end

        # Simply makes sure that all of the if children are typed. Also
        # checks that the if condition actually returns a boolean.
        # TODO: Want to change if to call to_b or something?
        def visit_if(node)
            node.condition.accept self
            with_new_scope { node.then.accept self }
            with_new_scope { node.else.accept self } if node.else
            raise "Expected condition in if to be a boolean" if node.condition.type != mod["Bool"]
        end

        # Makes sure that every child of the for loop is typed. Also
        # assures that the condition in the loop is of type Bool.
        def visit_for(node)
            node.init.accept self if node.init
            node.cond.accept self
            node.step.accept self if node.step
            with_new_scope { node.body.accept self }
            raise "Expected condition in loop to be a boolean" if node.cond.type != mod["Bool"]
        end

        # Evaluates the object expression and makes sure that the type
        # the member is accessed on actually has the specified variable.
        # Assigns the type to the type of the instance variable, or errors.
        def visit_member_access(node)
            node.object.accept self
            obj_type = node.object.type
            raise "Cannot access member of primitive type" if obj_type.is_a? PrimitiveType
            raise "Unknown member #{node.field.value} on object of type #{obj_type.name}" unless obj_type.instance_variables[node.child.value]
            node.type = obj_type.instance_variables[node.child.value]
        end

        # Sets the type of the New node to the object it creates, and
        # optionally assigns a constructor to it (if there is one).
        def visit_new(node)
            node.args.each {|arg| arg.accept self}
            raise "Undefined type '#{node.type}'" unless mod[node.type]
            node.type = mod[node.type]

            if (fn = find_overloaded_method(node.type.functions, "create", node.args)) then
                node.target_constructor = fn
            end
        end

        # Loops through all nodes in the body to type them. Also errors
        # when code is found after an if statement that always returns.
        def visit_body(node)
            node.nodes.each_with_index do |n, index|
                n.accept self
                raise "Unreachable code." if n.is_a?(If) && n.definitely_returns? && index != node.nodes.size - 1
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
