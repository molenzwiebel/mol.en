
module Molen
    class ASTNode; attr_accessor :type; end
    class Call; attr_accessor :target_function; end
    class New; attr_accessor :target_constructor; end
    class Import; attr_accessor :imported_body; end
    class ExternalFuncDef; attr_accessor :owner_type; end
    class Function
        attr_accessor :type_scope, :owner_type, :is_prototype_typed, :is_body_typed

        def add_overrider(node)
            overriding_functions[node.owner_type] = node
        end

        def overriding_functions
            @overriding_functions ||= {}
        end
    end
    class Body
        attr_accessor :referenced_identifiers

        def reference(name)
            @referenced_identifiers ||= []
            @referenced_identifiers << name unless @referenced_identifiers.include?(name)
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
            @current_body, old = node, @current_body
            node.each { |n| n.accept self }
            @current_body = old
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

        def visit_null(node)
            node.type = VoidType.new
        end

        def visit_size_of(node)
            node.target_type = node.target_type.resolve(self) || node.raise("Undefined type #{node.target_type.to_s}")
            node.type = program.long
        end

        def visit_pointer_of(node)
            node.target.accept self
            node.raise "Cannot take pointer of void" unless node.target.type
            node.type = PointerType.new program, node.target.type
        end

        def visit_identifier(node)
            node.type = @scope[node.value] || node.raise("Could not resolve variable #{node.value} in #{@current_function.name}")
            @current_body.reference node.value
        end

        def visit_constant(node)
            node.type = resolve_constant_type node.names
            node.raise "Could not resolve constant #{node.names.join(":")}" unless node.type
            node.type = node.type.metaclass
        end

        def visit_import(node)
            node.imported_body = program.import node.value, node.filename
        end

        def visit_native_body(node)
            node.type = @current_function.return_type
        end

        def visit_new_anonymous_function(node)
            node.args.each { |x| x.accept self }
            ret_type = node.return_type.resolve(self)
            node.raise "Undefined type '#{node.return_type.to_s}'" unless ret_type

            node.return_type = ret_type
            node.type = FunctionType.new ret_type, Hash[node.args.map{|x| [x.name, x.type]}], @scope.clone

            @current_function, old = node.type, @current_function
            with_new_scope do
                node.args.each do |arg|
                    @scope[arg.name] = arg.type
                end
                node.body.accept self
            end
            @current_function = old
        end

        def visit_new(node)
            node.args.each {|arg| arg.accept self}
            type = node.type.resolve(self)
            node.raise "Undefined type '#{node.type.to_s}'" unless type
            node.raise "Can only instantiate objects and structs" unless type.is_a?(ObjectType) or type.is_a?(StructType)
            node.type = type

            applicable_constructors = (type.functions["create"] || []).reject do |func|
                type_function_prototype(func) unless func.is_prototype_typed
                func.args.size != node.args.size
            end

            if (fn = find_overloaded_method(applicable_constructors, node.args)) then
                type_function_body(fn) unless fn.is_body_typed
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
            node.raise "Undefined type '#{node.type.to_s}'" unless node.type.resolve(self)
            current_type.vars[node.name] = node.type = node.type.resolve(self)
        end

        def visit_assign(node)
            node.value.accept self

            if node.target.is_a?(Identifier) then
                type = @scope[node.target.value]
                @current_body.reference node.value

                unless type
                    type = @scope[node.target.value] = node.value.type
                end

                node.raise "Cannot assign #{node.value.type.full_name} to '#{node.target.value}' (a #{type.full_name})" unless node.value.type.upcastable_to?(type).first
                node.type = node.target.type = type
            else
                node.target.accept self
                node.raise "Cannot assign #{node.value.type.full_name} to '#{node.target.to_s}' (a #{node.target.type.full_name})" unless node.value.type.upcastable_to?(node.target.type).first
                node.type = node.target.type
            end
        end

        def visit_member_access(node)
            node.object.accept self
            obj_type = node.object.type
            node.raise "Can only access members of objects and structs. Tried to access #{node.field.value} on #{obj_type.full_name}" unless obj_type.is_a?(ObjectType) or obj_type.is_a?(StructType)
            node.raise "Unknown member #{node.field.value} on object of type #{obj_type.full_name}" unless obj_type.vars[node.field.value]
            node.type = obj_type.vars[node.field.value]
        end

        def visit_cast(node)
            node.target.accept self
            type = node.type.resolve(self)
            node.raise "Cannot cast #{node.target.type.full_name} to #{type.full_name}" unless node.target.type.explicitly_castable_to?(type)
            node.type = type
        end

        def visit_function(node)
            receiver_type = current_type
            receiver_type = receiver_type.metaclass if node.is_static
            node.owner_type = receiver_type unless receiver_type.is_a?(Program)
            node.type_scope = type_scope.clone

            node.raise "Redefinition of #{receiver_type.name rescue "<top level>"}##{node.name} with same argument types" unless assure_unique(receiver_type.functions, node)

            # Check if this function overrides other functions.
            is_generic_or_other = node.owner_type.is_a?(ModuleType) ? node.owner_type.generic_types.keys.size == node.owner_type.generic_types.values.compact.size : true
            if node.owner_type && is_generic_or_other && receiver_type.functions[node.name] then
                existing_functions = receiver_type.functions[node.name]
                overrides_func = existing_functions.find do |func|
                    next false if func.args.size != node.args.size

                    ret_type = func.is_prototype_typed ? func.return_type.name : func.return_type.to_s
                    arg_types = func.is_prototype_typed ? func.args.map(&:type).map(&:name) : func.args.map(&:type).map(&:to_s)

                    node.return_type.to_s == ret_type && node.args.map(&:type).map(&:to_s) == arg_types && node.type_vars.size == func.type_vars.size
                end

                overrides_func.add_overrider node if overrides_func
                type_function_prototype(node) if overrides_func && overrides_func.is_prototype_typed
                type_function_body(node) if overrides_func && overrides_func.is_body_typed
            end

            receiver_type.functions.has_key?(node.name) ? receiver_type.functions[node.name] << node : receiver_type.functions[node.name] = [node]
        end

        def visit_return(node)
            node.raise "Cannot return if not in a function!" unless @current_function
            node.value.accept self if node.value
            node.type = node.value ? node.value.type : VoidType.new

            node.raise "Cannot return void from non-void function" if node.value.nil? && @current_function.return_type.is_a?(VoidType)
            node.raise "Cannot return value of type #{node.type.full_name} from function returning type #{@current_function.return_type.full_name}" unless node.type.upcastable_to?(@current_function.return_type).first
        end

        def type_function_prototype(node)
            with_type_scope(node.type_scope) do
                return_type = node.return_type.resolve(self)
                node.raise "Could not resolve function #{node.name}'s return type! (#{node.return_type.to_s} given)" unless return_type
                node.return_type = return_type
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

            node.raise "Function #{node.name} has a path that does not return!" unless node.body.returns? or node.return_type.is_a?(VoidType)
        end

        def visit_function_arg(node)
            node.type = node.type.resolve(self)
            node.raise "Undefined type #{node.type.to_s} (referenced from argument #{node.name})" unless node.type
        end

        def visit_class_def(node)
            parent = node.superclass ? node.superclass.resolve(self) : program.object
            node.raise "Could not resolve supertype #{node.superclass.to_s}." unless parent

            existing_type = current_type.types[node.name]
            existing_type = current_type.types[node.name] = ObjectType.new(node.name, parent, current_type, Hash[node.type_vars.map { |e| [e.names.join(":"), nil] }]) unless existing_type
            existing_type.nodes << node.body

            type_scope.push existing_type
            node.body.accept(self) unless existing_type.generic_types.size > 0
            type_scope.pop
        end

        def visit_struct_def(node)
            type = current_type.types[node.name]
            node.raise "Redefinition of #{node.name} in same scope" if type
            node.type = current_type.types[node.name] = StructType.new(node.name, current_type) unless type
            node.type.nodes << node.body

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
                node.raise "Tried to call method on void" if scope.is_a?(VoidType)
            else
                scope = program
            end

            function = nil

            if node.type_vars.size == 0 then
                function = find_function(scope, node.name, node.args, node.block)
            else
                vars = node.type_vars.map {|x| x.resolve(self)}
                node.raise "Could not resolve all type args." if vars.include?(nil)
                name = node.name + "<" + vars.map(&:full_name).join(", ") + ">"

                function = find_function(scope, name, node.args, node.block)
                unless function
                    untyped_function = (scope.functions[node.name] || []).reject do |func|
                        func.args.size != (node.block ? node.args.size + 1 : node.args) || func.type_vars.size != vars.size || func.args.last.type.arg_types.size != node.block.arg_names.size
                    end.first
                    node.raise "Undefined generic function #{node.name}" unless untyped_function

                    # Prevent cloning of these two
                    sc, untyped_function.type_scope = untyped_function.type_scope, nil
                    untyped_function.owner_type = nil
                    typed_func = DeepClone.clone(untyped_function)
                    typed_func.name = name
                    with_type_scope(sc) { typed_func.accept self }

                    type_lookup_scope = {}
                    vars.each_with_index do |var, i|
                        type_lookup_scope[untyped_function.type_vars[i].names.first] = var
                    end

                    typed_func.type_scope << FunctionTypeScope.new(type_lookup_scope)
                    type_function_prototype(typed_func)

                    function = typed_func
                end
            end

            node.raise "No function named #{node.name} with matching argument types found (#{node.args.map(&:type).map(&:full_name).join(",")})!" unless function

            if node.block then
                block_type = function.args.last.type
                block_arg = NewAnonymousFunction.new nil, nil, nil

                block_arg.body = node.block.body
                block_arg.return_type = block_type.return_type
                block_arg.args = node.block.arg_names.each_with_index.map { |n,i| FunctionArg.new n, block_type.args.values[i] }
                block_arg.type = FunctionType.new block_type.return_type, Hash[block_arg.args.map{|x| [x.name, x.type]}], @scope.clone

                @current_function, old = block_arg.type, @current_function
                with_new_scope do
                    block_arg.args.each do |arg|
                        @scope[arg.name] = arg.type
                    end
                    block_arg.body.accept self
                end
                @current_function = old

                node.args << block_arg
            end

            type_function_body(function) unless function.is_a?(ExternalFuncDef) or function.is_body_typed
            node.type = function.return_type
            node.target_function = function

            node.object.type.use_function(function) if node.object && node.object.type.is_a?(ObjectType)
        end

        def find_function(scope, name, args, block, type_var_size = 0)
            possible_functions = (scope.functions[name] || []).reject do |func|
                if func.is_a?(ExternalFuncDef) then
                    next func.args.size != args.size
                else
                    next true if type_var_size != func.type_vars.size
                    type_function_prototype(func) unless func.is_prototype_typed

                    if block then
                        next true if func.args.size < 1
                        next true unless func.args.last.type.is_a?(FunctionType)
                        next true if func.args.last.type.args.size != block.arg_names.size
                    end

                    next func.args.size != (block ? args.size + 1 : args.size) || func.type_vars.size != type_var_size
                end
            end
            find_overloaded_method(possible_functions, args)
        end

        def visit_external_def(node)
            existing_type = current_type.types[node.name]
            node.raise "Cannot define external with name #{node.name}: #{node.name} was already defined elsewhere" unless existing_type.nil? || existing_type.is_a?(ExternType)

            node.type = existing_type || (current_type.types[node.name] = ExternType.new(node.name, current_type))
            node.type.libnames << node.location if node.location

            type_scope.push node.type
            node.body.accept self
            type_scope.pop
        end

        def visit_external_func_def(node)
            node.args.each { |arg| arg.accept self }
            node.return_type = node.return_type ? node.return_type.resolve(self) : nil

            current_type.functions[node.name] = (current_type.functions[node.name] || []) << node
        end

        def visit_module_def(node)
            type = current_type.types[node.name]
            if type then
                node.raise "#{node.full_name} was already defined but not a module!" unless type.class == ModuleType
            else
                current_type.types[node.name] = type = ModuleType.new node.name, current_type, {}, Hash[node.type_vars.map { |e| [e.names.join(":"), nil] }]
            end
            type.nodes << node.body

            type_scope.push type
            node.body.accept(self) unless type.generic_types.size > 0
            type_scope.pop
        end

        def visit_include(node)
            type = node.type.resolve(self)
            node.raise "Undefined type #{node.type.to_s}" unless type
            node.raise "#{node.type.to_s} was defined but not a module" unless type.class == ModuleType

            type.functions.each do |name, funcs|
                funcs.each do |f|
                    # Prevent cloning of these two
                    f.type_scope = nil
                    f.owner_type = nil
                end
                new_funcs = DeepClone.clone(funcs)
                new_funcs.each do |func|
                    func.accept self
                    func.type_scope << FunctionTypeScope.new(type.generic_types)
                end
            end
        end

        def visit_type_alias_def(node)
            node.raise "Redefinition of #{node.name}" if current_type.types[node.name]
            type = node.type.resolve(self)
            node.raise "Undefined type '#{node.type.to_s}'" unless type
            current_type.types[node.name] = AliasType.new node.name, type
        end

        def resolve_constant_type(names)
            type = nil
            name = names.first

            type_scope.reverse_each do |scope|
                if (!scope.is_a?(Program) && !scope.is_a?(FunctionTypeScope)) && scope.name == name then
                    type = scope
                    break
                end
                type = scope.lookup_type(name) and break
            end

            return nil unless type

            names.drop(1).each_with_index do |name, i|
                type = type.types[name] or node.raise("Undefined type #{node.names[0..i + 1].join ':'}")
            end

            type
        end

        private
        def current_type
            @type_scope.last.is_a?(FunctionTypeScope) ? @type_scope[0...-1].last : @type_scope.last
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
                return false if func.args == function.args && func.owner_type == function.owner_type && func.type_vars.size == function.type_vars.size
            end
            return true
        end

        def find_overloaded_method(options, args)
            matches = Hash.new {|h,k| h[k] = []}
            options.each do |func|
                total_dist, valid = 0, true

                args.map(&:type).each_with_index do |arg_type, i|
                    can, dist = arg_type.upcastable_to? func.args[i].type

                    valid = valid && can
                    next unless can
                    total_dist += dist
                end

                next unless valid
                matches[total_dist] << func
            end
            return nil if matches.size == 0

            dist, functions = matches.min_by {|k, v| k}
            return nil if functions and functions.size > 1
            functions.first
        end
    end
end
