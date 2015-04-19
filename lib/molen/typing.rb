
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
            @functions["putchar"] = Function.new "putchar", mod["Int"], [Arg.new("x", mod["Int"])]
            @functions["puts"] = Function.new "puts", mod["Int"], [Arg.new("x", mod["String"])]
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

        def visit_if(node)
            node.cond.accept self
            with_new_scope { node.then.accept self }
            with_new_scope { node.else.accept self } if node.else
            raise "Expected condition in if to be a boolean" if node.cond.type != mod["Bool"]
        end

        def visit_for(node)
            node.init.accept visitor if node.init
            node.cond.accept visitor
            node.step.accept visitor if node.step
            with_new_scope { node.body.accept visitor }
            raise "Expected condition in loop to be a boolean" if node.cond.type != mod["Bool"]
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
            node.type = mod[node.name]
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
            raise "Cannot invoke function with argument types '#{func_arg_types.map(&:name).join ", "}' with arguments '#{node_arg_types.map(&:name).join ", "}'" if func_arg_types != node_arg_types

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
            else
                @functions[node.name] = node
            end

            with_new_scope(false) do
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
                raise "Binary op #{node.op} requires both sides to be numeric" unless (left_type == mod["Double"] or left_type == mod["Int"]) and (right_type == mod["Double"] or right_type == mod["Int"])
                node.type = mod["Double"] if left_type == mod["Double"] or right_type == mod["Double"]
                node.type = mod["Int"] unless node.type
            elsif node.op == "&&" or node.op == "||" or node.op == "or" or node.op == "and" or node.op == "==" or node.op == "!=" or node.op == "<" or node.op == "<=" or node.op == ">" or node.op == ">=" then
                node.left.accept self
                node.right.accept self

                left_type = node.left.type
                right_type = node.right.type

                raise "Binary op #{node.op} requires both sides to be a bool" if (left_type != mod["Bool"] or right_type != mod["Bool"]) and (node.op == "&&" or node.op == "||" or node.op == "or" or node.op == "and")
                raise "Binary op #{node.op} requires both sides to be numeric" if ((left_type != mod["Double"] and left_type != mod["Int"]) or (right_type != mod["Double"] and right_type != mod["Int"])) and (node.op == "<" or node.op == "<=" or node.op == ">" or node.op == ">=")
                node.type = mod["Bool"]
            elsif node.op == "=" then
                node.right.accept self # Check value.

                old_type = @scope[node.left.value]
                raise "Undefined variable '#{node.left.value}'" unless old_type

                node.type = node.left.type = node.right.type
                raise "Cannot assign #{node.type.name} to '#{node.left.value}' (a #{old_type.name})" if old_type != node.type
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
            node.type = mod[node.name] || ObjectType.new(node.name, node.superclass)

            @classes[node.name] ||= {type: node.type, defs: {}}
            node.funcs.each {|func| func.accept self}
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