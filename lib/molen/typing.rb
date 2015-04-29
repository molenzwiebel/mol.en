
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

        # Types a return node and makes sure that the value can
        # be returned from that function.
        def visit_return(node)
            raise "Cannot return if not in a function!" unless @current_function
            node.value.accept self if node.value
            node.type = node.value.nil? ? nil : node.value.type

            # Both are void
            return if node.value.nil? and @current_function.return_type.nil?

            raise "Cannot return void from non-void function" unless node.value and @current_function.return_type
            raise "Cannot return value of type #{node.type.name} from function returning type #{@current_function.return_type.name}" unless node.type.castable_to?(@current_function.return_type).first
        end

        # Evaluates the object expression and makes sure that the type
        # the member is accessed on actually has the specified variable.
        # Assigns the type to the type of the instance variable, or errors.
        def visit_member_access(node)
            node.object.accept self
            obj_type = node.object.type
            raise "Cannot access member of primitive type" if obj_type.is_a? PrimitiveType
            raise "Unknown member #{node.field.value} on object of type #{obj_type.name}" unless obj_type.instance_variables[node.field.value]
            node.type = obj_type.instance_variables[node.field.value]
        end

        # Sets the type of the New node to the object it creates, and
        # optionally assigns a constructor to it (if there is one).
        def visit_new(node)
            node.args.each {|arg| arg.accept self}
            raise "Undefined type '#{node.type.value}'" unless mod[node.type.value]
            node.type = mod[node.type.value]

            if (fn = find_overloaded_method(node.type.functions, "create", node.args)) then
                node.target_constructor = fn
            end
        end

        # Loops through all nodes in the body to type them. Also errors
        # when code is found after an if statement that always returns.
        def visit_body(node)
            node.contents.each_with_index do |n, index|
                n.accept self
                raise "Unreachable code." if n.is_a?(If) && n.definitely_returns? && index != node.contents.size - 1
            end
            last = node.contents.last
            node.type = (last and last.is_a?(Return)) ? last.type : nil
        end

        # Checks the correct scope (either current if no object, or the objects
        # if called on something) for a matching method. If found, performs
        # type checks and assigns the target_function variable for codegen.
        def visit_call(node)
            node.args.each {|arg| arg.accept self}

            unless node.object.nil? then
                node.object.accept self
                function = find_overloaded_method node.object.type.functions, node.name, node.args
            else
                function = find_overloaded_method @functions, node.name, node.args
            end

            node_arg_types = node.args.map(&:type)
            extra_str = node.object ? " (on object of type #{node.object.type.name}) " : " "
            raise "No function with name '#{node.name}'#{extra_str}and matching parameters found (given #{node_arg_types.map(&:name).join ", "})" unless function

            node.type = function.return_type
            node.target_function = function
        end

        # Resolves the type of a function argument, or errors if
        # not found.
        def visit_function_arg(node)
            raise "Unknown type #{node.given_type} for argument #{name}." unless mod[node.given_type]
            node.type = mod[node.given_type]
        end

        # Resolves a function and registers it in the appropriate
        # scope.
        def visit_function(node)
            node.return_type = node.return_type ? mod[node.return_type] : nil
            node.args.each {|arg| arg.accept self}

            if node.owner then
                func_scope = node.owner.type.functions
                raise "Redefinition of #{node.owner.type.name}##{node.name} with same argument types" unless assure_unique func_scope, node.name, node.args.map(&:type)
                func_scope.has_local_key?(node.name) ? func_scope[node.name] << node : func_scope.define(node.name, [node])
            else
                raise "Redefinition of #{node.name} with same argument types" unless assure_unique @functions, node.name, node.args.map(&:type)
                (@functions[node.name] ||= []) << node
            end

            @current_function = node
            with_new_scope(false) do
                @scope.define "this", node.owner.type if node.owner
                node.args.each do |arg|
                    @scope.define arg.name, arg.type
                end
                node.body.accept self
            end
            @current_function = nil

            raise "Function #{node.name} has a path that does not return!" if !node.body.definitely_returns? && node.return_type != nil
        end

        # Types and validates the assignment of a variable. Defines
        # the variable if it wasn't set already.
        def visit_assign(node)
            node.value.accept self # Check value.

            if node.name.is_a? Identifier then
                old_type = @scope[node.name.value]
                unless old_type
                    old_type = node.value.type
                    @scope.define node.name.value, old_type
                end

                node.type = node.name.type = old_type
                raise "Cannot assign #{node.value.type.name} to '#{node.name.value}' (a #{old_type.name})" unless node.value.type.castable_to?(old_type).first
            else
                node.name.accept self
                raise "Cannot assign #{node.value.type.name} to '#{node.name.to_s}' (a #{node.name.type.name})" unless node.value.type.castable_to?(node.name.type).first
                node.type = node.name.type
            end
        end

        # Visits and types every variable and function of a
        # class. Also resolves and successfully inherits
        # superclasses.
        def visit_class_def(node)
            superclass = mod[node.superclass]
            raise "Class #{node.superclass} (superclass of #{node.name}) not found!" unless superclass
            node.type = mod.types[node.name] ||= ObjectType.new(node.name, superclass)

            node.instance_vars.each do |var|
                type = mod[var.type]
                raise "Unknown type #{var.type} (used in #{node.name}##{var.name})" unless type
                node.type.instance_variables.define var.name, type
            end
            node.functions.each { |func| func.accept self }
        end

        private
        def find_overloaded_method(in_scope, name, args)
            return nil if in_scope[name].nil? || !in_scope[name].is_a?(::Array) || in_scope[name].size == 0

            matches = {}
            in_scope[name].each do |func|
                next if func.args.size != args.size
                callable, dist = func.callable? args.map(&:type)
                next if not callable
                (matches[dist] ||= []) << func
            end
            return nil if matches.size == 0

            dist, functions = matches.min_by {|k, v| k}
            raise "Multiple functions named #{name} found matching argument set '#{args.map(&:type).map(&:name).join ", "}'. Be more specific!" if functions and functions.size > 1
            functions.first
        end

        def assure_unique(in_scope, name, arg_types)
            return true if not in_scope[name] or not in_scope[name].is_a?(Array) or in_scope[name].size == 0
            in_scope[name].each do |func|
                return false if func.args.map(&:type) == arg_types
            end
            return true
        end

        def with_new_scope(inherit = true, inherit_from = nil)
            old_scope = @scope
            @scope = inherit ? (Scope.new inherit_from || old_scope) : Scope.new
            yield
            @scope = old_scope
        end
    end
end
