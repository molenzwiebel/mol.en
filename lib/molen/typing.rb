
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
            @functions["putchar"] = Function.new "putchar", mod["int"], [Arg.new("x", mod["int"])]
            @functions["puts"] = Function.new "puts", mod["int"], [Arg.new("x", mod["String"])]
        end

        def visit_int(node)
            node.type = mod["int"]
        end

        def visit_double(node)
            node.type = mod["double"]
        end

        def visit_bool(node)
            node.type = mod["bool"]
        end

        def visit_str(node)
            node.type = mod["String"]
        end

        def visit_if(node)
            node.cond.accept self
            with_new_scope { node.then.accept self }
            with_new_scope { node.else.accept self } if node.else
            raise "Expected condition in if to be a boolean" if node.cond.type != mod["bool"]
        end

        def visit_for(node)
            node.init.accept self if node.init
            node.cond.accept self
            node.step.accept self if node.step
            with_new_scope { node.body.accept self }
            raise "Expected condition in loop to be a boolean" if node.cond.type != mod["bool"]
        end

        def visit_member(node)
            node.on.accept self
            obj_type = node.on.type
            raise "Unknown member #{node.child.value} on object of type #{obj_type.name}" unless obj_type.vars[node.child.value]
            node.type = obj_type.vars[node.child.value]
        end

        def visit_body(node)
            node.nodes.each_with_index do |n, index|
                n.accept self
                raise "Unreachable code because if statement always returns." if n.is_a?(If) and n.definitely_returns and index != node.nodes.size - 1
            end
            last = node.nodes.last
            node.type = (last and last.is_a?(Return)) ? last.type : nil
        end

        def visit_var(node)
            raise "Undefined variable '#{node.value}'" unless @scope[node.value]
            node.type = @scope[node.value]
        end

        def visit_new(node)
            node.args.each {|arg| arg.accept self}
            raise "Undefined class '#{node.name}'" unless @classes[node.name] or mod[node.name]
            node.type = @classes[node.name] ? @classes[node.name][:type] : mod[node.name]
        end

        def visit_return(node)
            node.value.accept self if node.value
            node.type = node.value.type if node.value

            func = get_closest_func node
            return unless func

            func_ret_str = func.ret_type.nil? ? "nothing" : "a #{func.ret_type.name}"
            actual_ret_str = node.type.nil? ? "nothing" : "a #{node.type.name}"
            raise "Cannot return #{actual_ret_str} from function #{func.name} (returns #{func_ret_str})" if node.type != func.ret_type
        end

        def get_closest_func(node)
            parent = node
            until parent.nil?
                return parent if parent.is_a? Function
                parent = parent.parent
            end
            nil
        end

        def visit_call(node)
            if node.on then
                node.on.accept self
                function = @classes[node.on.type.name][:defs][node.name]
            else
                function = @functions[node.name]
            end

            raise "Undefined function '#{node.name}'" unless function
            raise "Mismatched parameters for function #{node.name}: #{node.args.size} given, #{function.args.size} required" if node.args.size != function.args.size
            node.args.each {|arg| arg.accept self}

            func_arg_types = function.args.map(&:type)
            node_arg_types = node.args.map(&:type)
            raise "Cannot invoke function requiring types '#{func_arg_types.map(&:name).join ", "}' with arguments '#{node_arg_types.map(&:name).join ", "}'" unless is_method_callable? function, *node_arg_types

            node.type = function.ret_type
            node.target = function
        end

        def visit_arg(node)
            node.type = mod[node.type.name]
        end

        def visit_function(node)
            node.ret_type = node.ret_type.nil? ? nil : mod[node.ret_type.name]
            node.args.each {|arg| arg.accept self}

            clazz = node.parent
            has_clazz = clazz.is_a? ClassDef
            if has_clazz then
                @classes[clazz.name][:defs][node.name] = node
                args = [true, @classes[clazz.name][:type].vars]
            else
                @functions[node.name] = node
                args = [false]
            end
            with_new_scope(*args) do
                @scope.define "this", @classes[clazz.name][:type] if has_clazz
                node.args.each do |arg|
                    @scope.define arg.name, arg.type
                end
                node.body.accept self
            end

            last = node.body.nodes.last
            has_return = node.body.definitely_returns or (last and last.is_a?(Return))
            raise "Function #{node.name} may not return a value!" if !has_return and node.ret_type != nil
        end

        def visit_binary(node)
            if node.op == "+" or node.op == "-" or node.op == "*" or node.op == "/" then
                node.left.accept self
                node.right.accept self

                left_type = node.left.type
                right_type = node.right.type
                raise "Binary op #{node.op} requires both sides to be numeric" unless (left_type == mod["double"] or left_type == mod["int"]) and (right_type == mod["double"] or right_type == mod["int"])
                node.type = mod["double"] if left_type == mod["double"] or right_type == mod["double"]
                node.type = mod["int"] unless node.type
            elsif node.op == "&&" or node.op == "||" or node.op == "or" or node.op == "and" or node.op == "==" or node.op == "!=" or node.op == "<" or node.op == "<=" or node.op == ">" or node.op == ">=" then
                node.left.accept self
                node.right.accept self

                left_type = node.left.type
                right_type = node.right.type

                raise "Binary op #{node.op} requires both sides to be a bool" if (left_type != mod["bool"] or right_type != mod["bool"]) and (node.op == "&&" or node.op == "||" or node.op == "or" or node.op == "and")
                raise "Binary op #{node.op} requires both sides to be numeric" if ((left_type != mod["double"] and left_type != mod["int"]) or (right_type != mod["double"] and right_type != mod["int"])) and (node.op == "<" or node.op == "<=" or node.op == ">" or node.op == ">=")
                node.type = mod["bool"]
            elsif node.op == "=" then
                node.right.accept self # Check value.
                raise "Expected variable or member on left side of =" unless node.left.is_a? Var or node.left.is_a? Member

                if node.left.is_a? Var then
                    old_type = @scope[node.left.value]
                    raise "Undefined variable '#{node.left.value}'" unless old_type

                    node.type = node.left.type = node.right.type
                    raise "Cannot assign #{node.type.name} to '#{node.left.value}' (a #{old_type.name})" if old_type != node.type
                else
                    node.left.accept self
                    raise "Cannot assign #{node.left.type.name} to '#{node.left.to_s}' (a #{node.left.type.name})" if node.left.type != node.right.type
                    node.type = node.left.type = node.right.type
                end
            end
        end

        def visit_vardef(node)
            node.value.accept self if node.value
            defined_type = mod[node.type.name] if node.type
            raise "Conflicting types: var statement specified type #{defined_type.name} while being assigned value of type #{node.value.type.name}" if defined_type and node.value and defined_type != node.type

            node.type = defined_type || node.value.type
            raise "Vardef has no type?" unless node.type

            @scope.define node.name.value, node.type
        end

        def visit_classdef(node)
            superclass = mod[node.superclass]
            raise "Class #{node.superclass} (superclass of #{node.name}) not found!" unless superclass
            node.type = mod.types[node.name] ||= ObjectType.new(node.name, superclass)

            @classes[node.name] ||= {type: node.type, defs: {}}
            node.vars.each do |var|
                with_new_scope(false) { var.accept self }
                node.type.vars[var.name.value] = var.type
            end
            node.funcs.each { |func| func.accept self }
        end

        private
        def with_new_scope(inherit = true, inherit_from = nil)
            old_scope = @scope
            if inherit then
                @scope = Scope.new inherit_from || old_scope
            else
                @scope = Scope.new
            end
            yield
            @scope = old_scope
        end

        def is_method_callable?(func_node, *arg_types)
            return false if func_node.args.size != arg_types.size
            arg_types.each_with_index do |arg_type, i|
                can, dist = arg_type.castable_to func_node.args[i].type
                return false if not can
            end
            true
        end
    end
end