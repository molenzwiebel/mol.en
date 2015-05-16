
module Molen
    class ASTNode; attr_accessor :type; end
    class Call; attr_accessor :target_function; end
    class New; attr_accessor :target_constructor; end
    class Import; attr_accessor :imported_body; end
    class Function
        attr_accessor :type_scope, :is_prototype_typed, :is_body_typed, :owner_type

        def add_overrider(node)
            @overriding_functions = {} unless @overriding_functions
            @overriding_functions[node.owner_type.name] = node
        end

        def overriding_functions
            @overriding_functions || {}
        end
    end

    def type(tree, program)
        Molen.type tree, program
    end

    def self.type(tree, program)
        vis = TypingVisitor.new program
        tree.accept vis
        tree
    end

    class TypingVisitor < Visitor
        attr_accessor :program, :type_scope

        def initialize(prog)
            @program = prog
            @type_scope = [prog]

            @scope = {}
        end

        def visit_body(node)
            node.each { |n| n.accept self }
        end

        def visit_bool(node)
            node.type = program.bool
        end

        def visit_int(node)
            node.type = program.int
        end

        def visit_long(node)
            node.type = program.long
        end

        def visit_double(node)
            node.type = program.double
        end

        def visit_str(node)
            node.type = program.string
        end

        def visit_size_of(node)
            node.target_type.resolve(self) || node.raise("Undefined type #{node.target_type.to_s}")
            node.type = program.long
        end

        def visit_pointer_of(node)
            node.target.accept self
            node.raise "Cannot take pointer of void" unless node.target.type
            node.type = PointerType.new node.target.type
        end

        def visit_identifier(node)
            node.type = @scope[node.value] || node.raise("Could not resolve variable #{node.value}")
        end

        def visit_constant(node)
            node.type = UnresolvedSimpleType.new(node.value).resolve(self)
            node.raise "Could not resolve constant #{node.value}" unless node.type
            node.type = node.type.metaclass
        end

        def visit_new(node)
            node.args.each {|arg| arg.accept self}
            type = node.type.resolve(self)
            node.raise "Can only instantiate objects and structs" unless type.is_a?(ObjectType) or type.is_a?(StructType)
            node.type = type

            applicable_constructors = (type.functions["create"] || []).reject do |func|
                type_function_prototype(func) unless func.is_prototype_typed
                func.args.size != node.args.size
            end

            if (fn = find_overloaded_method(applicable_constructors, node.args)) then
                type_function(fn) unless fn.is_body_typed
                node.target_constructor = fn
            end
        end

        def visit_if(node)
            node.condition.accept self
            node.if_body.accept self
            node.else_body.accept self if node.else_body
        end

        def visit_for(node)
            node.init.accept self if node.init
            node.cond.accept self
            node.step.accept self if node.step
            node.body.accept self
        end

        def visit_var_def(node)
            node.raise "Unexpected var def!" unless current_type.is_a?(ObjectType) || current_type.is_a?(StructType)
            node.raise "Redefinition of variable #{node.name}" if current_type.vars[node.name]
            node.raise "Undefined type '#{node.type.to_s}'" unless node.type.resolve(self) || current_type.generic_types.size > 0
            current_type.vars[node.name] = node.type = node.type.resolve(self) || node.type
        end

        def visit_assign(node)
            node.value.accept self

            if node.target.is_a?(Identifier) then
                type = @scope[node.target.value]

                unless type
                    type = @scope[node.target.value] = node.value.type
                end

                node.raise "Cannot assign #{node.value.type.name} to '#{node.target.value}' (a #{type.name})" unless node.value.type.upcastable_to?(type).first
                node.type = node.target.type = type
            else
                node.target.accept self
                node.raise "Cannot assign #{node.value.type.name} to '#{node.target.to_s}' (a #{node.target.type.name})" unless node.value.type.upcastable_to?(node.target.type).first
                node.type = node.target.type
            end
        end

        def visit_member_access(node)
            node.object.accept self
            obj_type = node.object.type
            node.raise "Can only access members of objects and structs. Tried to access #{node.field.value} on #{obj_type.name}" unless obj_type.is_a?(ObjectType) or obj_type.is_a?(StructType)
            node.raise "Unknown member #{node.field.value} on object of type #{obj_type.name}" unless obj_type.vars[node.field.value]
            node.type = obj_type.vars[node.field.value]
        end

        def visit_cast(node)
            node.target.accept self
            type = node.type.resolve(self)
            node.raise "Cannot cast #{node.target.type.name} to #{type.name}" unless node.target.type.explicitly_castable_to?(type)
            node.type = type
        end

        def visit_function(node)
            receiver_type = current_type
            receiver_type = receiver_type.metaclass if node.is_static
            node.owner_type = receiver_type unless receiver_type.is_a?(Program)
            node.type_scope = type_scope.clone

            node.raise "Redefinition of #{receiver_type.name rescue "<top level>"}##{node.name} with same argument types" unless assure_unique(receiver_type.functions, node)
            receiver_type.functions[node.name] = (receiver_type.functions[node.name] || []) << node
        end

        def visit_return(node)
            node.raise "Cannot return if not in a function!" unless @current_function
            node.value.accept self if node.value
            node.type = node.value.nil? ? nil : node.value.type

            # Both are void
            return if node.value.nil? and @current_function.return_type.nil?

            node.raise "Cannot return void from non-void function" unless node.value and @current_function.return_type
            node.raise "Cannot return value of type #{node.type.name} from function returning type #{@current_function.return_type.name}" unless node.type.upcastable_to?(@current_function.return_type).first
        end

        def type_function_prototype(node)
            with_type_scope(node.type_scope) do
                ret_type = node.return_type ? node.return_type.resolve(self) : nil
                node.raise "Could not resolve function #{node.name}'s return type! (#{node.return_type.to_s} given)" if node.return_type && ret_type.nil?
                node.return_type = ret_type
                node.args.each {|arg| arg.accept self}
                node.is_prototype_typed = true
            end
        end

        def type_function_body(node)
            node.is_body_typed = true

            node.overriding_functions.each do |type, overriding_func|
                type_function_prototype(overriding_func) unless overriding_func.is_prototype_typed
                type_function_body(overriding_func) unless overriding_func.is_body_typed
            end

            with_type_scope(node.type_scope) do
                @current_function, prev = node, @current_function
                with_new_scope(false) do
                    @scope["this"] = node.owner_type if node.owner_type
                    node.args.each do |arg|
                        @scope[arg.name] = arg.type
                    end
                    node.body.accept self
                end
                @current_function = prev
            end
        end

        def visit_function_arg(node)
            node.type = node.type.resolve(self)
            node.raise "Undefined type #{node.type.to_s} (referenced from argument #{node.name})" unless node.type
        end

        def visit_class_def(node)
            parent = node.superclass ? node.superclass.resolve(self) : program.object
            node.raise "Could not resolve supertype #{node.superclass.to_s}." unless parent

            existing_type = current_type.types[node.name]
            existing_type = current_type.types[node.name] = ObjectType.new(node.name, parent, Hash[node.type_vars.map { |e| [e.name, nil] }]) unless existing_type

            type_scope.push existing_type
            node.body.accept self
            type_scope.pop
        end

        def visit_struct_def(node)
            type = current_type.types[node.name]
            node.raise "Redefinition of #{node.name} in same scope" if type
            node.type = current_type.types[node.name] = StructType.new(node.name) unless type

            type_scope.push node.type
            node.body.accept self
            type_scope.pop
        end

        def visit_call(node)
            node.args.each {|arg| arg.accept self}

            scope = nil
            if node.object then
                node.object.accept self
                scope = node.object.type
            else
                scope = current_type
            end

            possible_functions = (scope.functions[node.name] || []).reject do |func|
                type_function_prototype(func) unless func.is_prototype_typed
                func.args.size != node.args.size
            end
            function = find_overloaded_method(possible_functions, node.args)
            raise "No function named #{node.name} with matching argument types found!" unless function

            type_function_body(function) unless function.is_body_typed
            node.type = function.return_type
            node.target_function = function
        end

        private
        def current_type
            @type_scope.last
        end

        def with_new_scope(inherit = true)
            old = @scope
            @scope = inherit ? ParentHash.new(old) : {}
            yield
            @scope = old
        end

        def with_type_scope(scope)
            @type_scope, old = scope, @type_scope
            yield
            @type_scope = old
        end

        def assure_unique(scope, function)
            return true if scope[function.name].nil? || scope[function.name].size == 0
            scope[function.name].each do |func|
                return false if func.args == function.args && func.owner_type == function.owner_type
            end
            return true
        end

        def find_overloaded_method(options, args)
            matches = Hash.new {|h,k| h[k] = []}
            options.each do |func|
                total_dist, valid = 0, true

                func.args.map(&:type).each_with_index do |arg_type, i|
                    can, dist = arg_type.upcastable_to? args[i].type
                    valid = valid && can
                    next unless can
                    total_dist += dist
                end

                next unless valid
                matches[total_dist] << func
            end
            return nil if matches.size == 0

            dist, functions = matches.min_by {|k, v| k}
            node.raise "Multiple functions named #{name} found matching argument set '#{args.map(&:type).map(&:name).join ", "}'. Be more specific!" if functions and functions.size > 1
            functions.first
        end
    end
end
