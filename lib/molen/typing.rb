
module Molen
    class ASTNode; attr_accessor :type; end
    class Call; attr_accessor :target_function; end
    class New; attr_accessor :target_constructor; end
    class InstanceVariable; attr_accessor :owner; end
    class Function; attr_accessor :is_typed; end
    class Return; attr_accessor :func_ret_type; end

    def type(mod, tree)
        Molen.type(mod, tree)
    end

    def self.type(mod, tree)
        vis = TypingVisitor.new mod
        tree.accept vis
        tree
    end

    class TypingVisitor < Visitor
        attr_accessor :mod

        def initialize(mod)
            @mod = mod

            @scope = Scope.new
            @functions = Scope.new
            @functions["putchar"] = [Function.new(nil, "putchar", mod["Int"], [FunctionArg.new("x", mod["Int"])], NativeBody.new(lambda { |arg|
                putc_func = llvm_mod.functions["putchar"] || llvm_mod.functions.add("putchar", [LLVM::Int], LLVM::Int)
                builder.ret builder.call putc_func, arg
            }))]
            @functions["puts"] = [Function.new(nil, "puts", mod["Int"], [FunctionArg.new("x", mod["String"])], NativeBody.new(lambda { |arg|
                puts_func = llvm_mod.functions["puts"] || llvm_mod.functions.add("puts", [LLVM::Pointer(LLVM::Int8)], LLVM::Int)
                str = builder.struct_gep(arg, 1)
                builder.ret builder.call puts_func, builder.load(str)
            }))]
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

        def visit_long(node)
            node.type = mod["Long"]
        end

        # Tries to find the specified identifier in the current scope,
        # and assigns the type of the identifier if found. Errors otherwise
        def visit_identifier(node)
            node.raise "Undefined variable '#{node.value}'" unless @scope[node.value]
            node.type = @scope[node.value]
        end

        # Tries to find the specified constant in the current scope,
        # and assigns the type of the constant if found. Errors otherwise
        def visit_constant(node)
            node.raise "Undefined constant '#{node.value}'" unless resolve_type node.value
            node.type = resolve_type node.value
        end

        def visit_cast(node)
            node.expr.accept self
            type = resolve_type node.type
            node.raise "Cannot cast #{node.expr.type.name} to #{type.name}" unless node.expr.type.castable_to?(type).first
            node.type = type
        end

        def visit_pointer_of(node)
            node.expr.accept self
            node.type = PointerType.new mod, node.expr.type
        end

        def visit_pointer_malloc(node)
            node.raise "Expected 2 arguments to Pointer.malloc" if node.args.size != 2

            node.args[0].accept self
            node.args[1].accept self

            node.raise "Expected first argument to Pointer.malloc to be a type, #{node.args[0].type.name rescue "void"} received" unless node.args[0].is_a?(Constant)
            node.raise "Expected second argument to Pointer.malloc to be an int, #{node.args[1].type.name rescue "void"} received" unless node.args[1].type == mod["Int"]

            node.type = PointerType.new mod, node.args[0].type
        end

        # Tries to find the specified instance variable and errors
        # if the variable was not found.
        def visit_instance_variable(node)
            node.raise "Cannot access instance variables if not in a function" unless @current_function
            node.raise "Cannot access instance variables if not in a class function" unless @current_function.owner
            obj_type = @current_function.owner.type
            node.raise "Cannot access instance variable of primitive type" if obj_type.is_a? PrimitiveType
            node.raise "Unknown instance variable #{node.value} on object of type #{obj_type.name}" unless obj_type.instance_variables[node.value]
            node.type = obj_type.instance_variables[node.value]
            node.owner = obj_type
        end

        # Simply makes sure that all of the if children are typed. Also
        # checks that the if condition actually returns a boolean.
        # TODO: Want to change if to call to_b or something?
        def visit_if(node)
            node.condition.accept self
            with_new_scope { node.then.accept self }
            with_new_scope { node.else.accept self } if node.else
            node.raise "Expected condition in if to be a boolean" if node.condition.type != mod["Bool"]
        end

        # Makes sure that every child of the for loop is typed. Also
        # assures that the condition in the loop is of type Bool.
        def visit_for(node)
            node.init.accept self if node.init
            node.cond.accept self
            node.step.accept self if node.step
            with_new_scope { node.body.accept self }
            node.raise "Expected condition in loop to be a boolean" if node.cond.type != mod["Bool"]
        end

        # We just assume that the native body returns the same value as the function its in.
        def visit_native_body(node)
            node.type = @current_function.return_type
        end

        # Types a return node and makes sure that the value can
        # be returned from that function.
        def visit_return(node)
            node.raise "Cannot return if not in a function!" unless @current_function
            node.value.accept self if node.value
            node.type = node.value.nil? ? nil : node.value.type
            node.func_ret_type = @current_function.return_type

            # Both are void
            return if node.value.nil? and @current_function.return_type.nil?

            node.raise "Cannot return void from non-void function" unless node.value and @current_function.return_type
            node.raise "Cannot return value of type #{node.type.name} from function returning type #{@current_function.return_type.name}" unless node.type.castable_to?(@current_function.return_type).first
        end

        # Evaluates the object expression and makes sure that the type
        # the member is accessed on actually has the specified variable.
        # Assigns the type to the type of the instance variable, or errors.
        def visit_member_access(node)
            node.object.accept self
            obj_type = node.object.type
            node.raise "Can only access members of objects and structs" unless obj_type.is_a?(ObjectType) or obj_type.is_a?(StructType)
            node.raise "Unknown member #{node.field.value} on object of type #{obj_type.name}" unless obj_type.instance_variables[node.field.value]
            node.type = obj_type.instance_variables[node.field.value]
        end

        # Sets the type of the New node to the object it creates, and
        # optionally assigns a constructor to it (if there is one).
        def visit_new(node)
            node.args.each {|arg| arg.accept self}
            type = resolve_type node.type.value
            node.raise "Cannot instantiate primitive" if type.is_a? PrimitiveType
            node.type = type

            if (fn = find_overloaded_method(node, node.type.functions, "create", node.args)) then
                type_function(fn) unless fn.is_typed
                node.target_constructor = fn
            end
        end

        def visit_new_array(node)
            if node.type then
                node.type = resolve_type node.type
            else
                node.raise "Cannot deduce type of array: No initial elements or type given." if node.elements.size == 0
                node.elements.each { |el| el.accept self }
                available_types = node.elements.first.type.inheritance_chain
                node.elements.drop(1).each do |el|
                    types = el.type.inheritance_chain
                    available_types.each { |t| available_types.delete(t) unless types.include? t }
                end
                node.raise "Cannot deduce type of array: No common superclass found." if available_types.size == 0
                node.type = resolve_type available_types.first.name + "[]" # Pretty dirty hack.
            end
        end

        # Loops through all nodes in the body to type them. Also errors
        # when code is found after an if statement that always returns.
        def visit_body(node)
            node.contents.each_with_index do |n, index|
                n.accept self
            end
            last = node.contents.last
            node.type = (last and last.is_a?(Return)) ? last.type : nil
        end

        # Checks the correct scope (either current if no object, or the objects
        # if called on something) for a matching method. If found, performs
        # type checks and assigns the target_function variable for codegen.
        def visit_call(node)
            node.args.each {|arg| arg.accept self}

            if node.object.is_a? Constant then
                node.object.accept self
                function = find_overloaded_method node, node.object.type.class_functions, node.name, node.args
            elsif node.object then
                node.object.accept self
                node.raise "Cannot call function on void (tried to call #{node.name})." unless node.object.type
                function = find_overloaded_method node, node.object.type.functions, node.name, node.args
            else
                function = find_overloaded_method node, @functions, node.name, node.args
            end

            node_arg_types = node.args.map(&:type)
            extra_str = node.object ? " (on object of type #{node.object.type.name}) " : " "
            node.raise "No function with name '#{node.name}'#{extra_str}and matching parameters found (given #{node_arg_types.map(&:name).join ", "})." unless function

            type_function(function) unless function.is_a?(ExternalFunc) or function.is_typed

            node.type = function.return_type
            node.target_function = function
        end

        # Resolves the type of a function argument, or errors if
        # not found.
        def visit_function_arg(node)
            node.raise "Unknown type #{node.type} for argument #{name}." unless resolve_type(node.type)
            node.type = resolve_type node.type
        end

        # Resolves a function and registers it in the appropriate
        # scope.
        def visit_function(node)
            node.return_type = node.return_type ? resolve_type(node.return_type) : nil
            node.args.each {|arg| arg.accept self}

            func_scope = @functions
            func_scope = node.owner.type.functions if node.owner

            node.raise "Redefinition of #{node.owner.type.name rescue "<top level>"}##{node.name} with same argument types" unless assure_unique func_scope.this, node.name, node.args.map(&:type)
            func_scope.has_local_key?(node.name) ? func_scope[node.name] << node : func_scope.define(node.name, [node])
        end

        def type_function(node)
            old_func = @current_function
            node.is_typed = true if node.is_a?(Function)

            @current_function = node
            with_new_scope(false) do
                @scope.define "this", node.owner.type if node.owner
                node.args.each do |arg|
                    @scope.define arg.name, arg.type
                end
                node.body.accept self
            end
            @current_function = old_func

            node.raise "Function #{node.name} has a path that does not return! #{node.body.definitely_returns?}, #{node.return_type.class.name}" if !node.body.definitely_returns? && node.return_type != nil
        end

        def visit_array_access(node)
            node.array.accept(self)
            node.index.accept(self)
            node.raise "Cannot index array: Target is not an array" unless node.array.type.is_a? ArrayType
            node.raise "Cannot index array with type #{node.index.type.name}, Int expected" unless node.index.type == mod["Int"]
            node.type = node.array.type.element_type
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
                node.raise "Cannot assign void to #{node.name.value}" if node.value.type.nil? && !(old_type.is_a?(ObjectType) || old_type.is_a?(PointerType) || old_type.is_a?(ArrayType))
                node.raise "Cannot assign #{node.value.type.name} to '#{node.name.value}' (a #{old_type.name})" unless node.value.type.castable_to?(old_type).first
            else
                node.name.accept self
                node.raise "Cannot assign #{node.value.type.name} to '#{node.name.to_s}' (a #{node.name.type.name})" unless node.value.type.castable_to?(node.name.type).first
                node.type = node.name.type
            end
        end

        # Visits and types every variable and function of a
        # class. Also resolves and successfully inherits
        # superclasses.
        def visit_class_def(node)
            superclass = mod[node.superclass]
            node.raise "Class #{node.superclass} (superclass of #{node.name}) not found!" unless superclass
            node.type = mod.types[node.name] ||= ObjectType.new(node.name, superclass)

            @scope.define node.name, node.type unless @scope.has_local_key? node.name

            node.instance_vars.each do |var|
                type = resolve_type var.type
                node.raise "Unknown type #{var.type} (used in #{node.name}##{var.name})" unless type
                node.type.instance_variables.define var.name, type
            end
            node.functions.each { |func| func.accept self }
            node.class_functions.each do |func|
                func.accept self
                node.type.class_functions[func.name] = (node.type.class_functions[func.name] || []) << func
            end
        end

        def visit_struct_def(node)
            node.type = mod[node.name] = StructType.new(node.name, {})

            node.vars.each do |v|
                type = resolve_type v.type
                node.raise "Unknown type #{var.type} (used in #{node.name}##{var.name})" unless type
                node.type.instance_variables[v.name] = type
            end
        end

        def visit_external_def(node)
            existing_type = mod[node.name]
            node.raise "Cannot define external with name #{node.name}: #{node.name} was already defined elsewhere" unless existing_type.nil? or existing_type.is_a? ExternalType

            node.type = existing_type || (mod[node.name] = ExternalType.new(node.name))
            node.type.locations << node.location if node.location

            node.functions.each do |func|
                func.accept self
                node.type.class_functions[func.name] = (node.type.class_functions[func.name] || []) << func
            end
        end

        def visit_external_func(node)
            node.return_type = node.return_type ? resolve_type(node.return_type) : nil
            node.args.each {|arg| arg.accept self}
        end

        private
        def find_overloaded_method(node, in_scope, name, args)
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
            node.raise "Multiple functions named #{name} found matching argument set '#{args.map(&:type).map(&:name).join ", "}'. Be more specific!" if functions and functions.size > 1
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

        def resolve_type(name)
            return mod[name] if mod[name]

            if name[0] == "*" then
                return mod[name] = PointerType.new(mod, resolve_type(name[1..-1]))
            end

            unless name.include? "["
                # It is not an array and it wasn't in mod, which means it is undefined
                raise "Undefined type '#{name}'"
            end

            mod[name] = ArrayType.new mod, resolve_type(name[0...-2])
        end
    end
end

class NilClass
    def castable_to?(other)
        return other.is_a?(ObjectType) || other.is_a?(PointerType) || other.is_a?(ArrayType), 0
    end
end
