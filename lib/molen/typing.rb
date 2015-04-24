
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

    class New
        # Same as Call.
        attr_accessor :target
    end

    class Function
        # The "this" type. This is used for casting objects when a parent
        # class with differing instance variables should be called.
        attr_accessor :this_type
    end

    def self.type(body, mod)
        visitor = TypingVisitor.new mod
        body.accept visitor
    end

    def self.parse_and_type(body, mod)
        body = parse body
        type body, mod
        body
    end

    class TypingVisitor < Visitor
        attr_accessor :mod

        def initialize(mod)
            @mod = mod

            @scope = Scope.new
            @functions = {}
            @functions["putchar"] = [Function.new("putchar", mod["int"], [Arg.new("x", mod["int"])])]
            @functions["puts"] = [Function.new("puts", mod["int"], [Arg.new("x", mod["str"])])]
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
            node.type = mod["str"]
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
            raise "Undefined class '#{node.name}'" unless mod[node.name]
            node.type = mod[node.name]

            func_scope = node.type.functions
            if (fn = find_overloaded_method(func_scope, "create", *node.args)) then
                node.target = fn
            end
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

        def visit_call(node)
            node.args.each {|arg| arg.accept self}

            if node.on then
                node.on.accept self
                function = find_overloaded_method mod[node.on.type.name].functions, node.name, *node.args
            else
                function = find_overloaded_method @functions, node.name, *node.args
            end

            node_arg_types = node.args.map(&:type)
            extra_str = node.on ? " (on object of type #{node.on.type.name}) " : " " 
            raise "No function with name '#{node.name}'#{extra_str}and matching parameters found (given #{node_arg_types.map(&:name).join ", "})" unless function

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
                func_scope = mod[clazz.name].functions
                raise "Redefinition of #{clazz.name}##{node.name} with same argument types" unless assure_unique func_scope, node.name, *node.args.map(&:type)
                func_scope.this.has_key?(node.name) ? func_scope[node.name] << node : func_scope.define(node.name, [node])
                args = [true, mod[clazz.name].vars]
            else
                raise "Redefinition of #{node.name} with same argument types" unless assure_unique @functions, node.name, *node.args.map(&:type)
                (@functions[node.name] ||= []) << node
                args = [false]
            end
            with_new_scope(*args) do
                @scope.define "this", mod[clazz.name] if has_clazz
                node.this_type = mod[clazz.name] if has_clazz
                node.args.each do |arg|
                    @scope.define arg.name, arg.type
                end
                node.body.accept self
            end

            last = node.body.nodes.last
            has_return = node.body.definitely_returns or (last and last.is_a?(Return))
            raise "Function #{node.name} may not return a value!" if !has_return and node.ret_type != nil
        end

        def visit_assign(node)
            node.value.accept self # Check value.
            raise "Expected variable or member on left side of =" unless node.name.is_a? Var or node.name.is_a? Member

            if node.name.is_a? Var then
                old_type = @scope[node.name.value]
                raise "Undefined variable '#{node.name.value}'" unless old_type

                node.type = node.name.type = old_type
                raise "Cannot assign #{node.type.name} to '#{node.name.value}' (a #{old_type.name})" unless node.value.type.castable_to(old_type).first
            else
                node.name.accept self
                raise "Cannot assign #{node.name.type.name} to '#{node.name.to_s}' (a #{node.name.type.name})" unless node.value.type.castable_to(node.name.type).first
                node.type = node.name.type
            end
        end

        def visit_vardef(node)
            node.value.accept self if node.value
            defined_type = mod[node.type.name] if node.type

            valid = false
            if defined_type and not node.value then
                valid = true
                node.type = defined_type
            elsif node.value and not defined_type then
                valid = true
                node.type = node.value.type
            elsif node.value and defined_type then
                valid, dist = node.value.type.castable_to defined_type
                node.type = defined_type
            end
            raise "Conflicting types: var statement specified type #{defined_type.name} while being assigned value of type #{node.value.type.name}" if not valid
            raise "Vardef has no type?" unless node.type

            @scope.define node.name.value, node.type
        end

        def visit_classdef(node)
            superclass = mod[node.superclass]
            raise "Class #{node.superclass} (superclass of #{node.name}) not found!" unless superclass
            node.type = mod.types[node.name] ||= ObjectType.new(node.name, superclass)

            node.vars.each do |var|
                with_new_scope(false) { var.accept self }
                node.type.vars.define var.name.value, var.type
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

        def assure_unique(in_scope, name, *arg_types)
            return true if not in_scope[name] or not in_scope[name].is_a?(Array) or in_scope[name].size == 0
            in_scope[name].each do |func|
                return false if func.args.map(&:type) == arg_types
            end
            return true
        end

        def get_closest_func(node)
            parent = node
            until parent.nil?
                return parent if parent.is_a? Function
                parent = parent.parent
            end
            nil
        end

        def is_method_callable?(func_node, *arg_types)
            return false, -1 if func_node.args.size != arg_types.size
            total_dist = 0
            arg_types.each_with_index do |arg_type, i|
                can, dist = arg_type.castable_to func_node.args[i].type
                return false, -1 if not can
                total_dist += dist
            end
            return true, total_dist
        end

        def find_overloaded_method(in_scope, name, *args)
            return nil if not in_scope[name] or not in_scope[name].is_a?(::Array) or in_scope[name].size == 0
            matches = {}
            in_scope[name].each do |func|
                next if func.args.size != args.size
                callable, dist = is_method_callable? func, *args.map(&:type)
                next if not callable
                (matches[dist] ||= []) << func
            end
            return nil if matches.size == 0

            dist, functions = matches.min_by {|k, v| k}
            raise "Multiple functions named #{name} found matching argument set '#{args.map(&:type).map(&:name).join ", "}'. Be more specific!" if functions and functions.size > 1
            functions.first
        end
    end
end