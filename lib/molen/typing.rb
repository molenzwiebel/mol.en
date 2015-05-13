
module Molen
    class ASTNode; attr_accessor :type; end
    class Call; attr_accessor :target_function; end
    class New; attr_accessor :target_constructor; end
    class Import; attr_accessor :imported_body; end
    class Function
        attr_accessor :is_prototype_typed, :is_body_typed, :owner_type

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
        attr_accessor :program

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

        def visit_function(node)
            current_type.functions[node.name] << node
            node.owner_type = current_type
        end

        def type_function_prototype(node)
            ret_type = node.return_type ? node.return_type.resolve(@type_scope) : nil
            node.raise "Could not resolve function #{node.name}'s return type! (#{node.return_type.to_s} given)" if node.return_type && ret_type.nil?
            node.return_type = ret_type
            node.args.each {|arg| arg.accept self}
            node.is_prototype_typed = true
        end

        def type_function_body(node)
            node.is_body_typed = true

            node.overriding_functions.each do |type, overriding_func|
                type_function_prototype(overriding_func) unless overriding_func.is_prototype_typed
                type_function_body(overriding_func) unless overriding_func.is_body_typed
            end

            with_new_scope(false) do
                @scope["this"] = node.owner_type if node.owner_type
                node.args.each do |arg|
                    @scope[arg.name] = arg.type
                end
                node.body.accept self
            end
        end

        def visit_function_arg(node)
            node.type = node.type.resolve(@type_scope)
            node.raise "Undefined type #{node.type.to_s} (referenced from argument #{node.name})" unless node.type
        end

        def visit_class_def(node)
            parent = node.superclass ? node.superclass.resolve(@type_scope) : program.object
            node.raise "Could not resolve supertype #{node.superclass.to_s}." unless parent

            existing_type = current_type.types[node.name]
            node.raise "Superclass mismatch." if existing_type && node.superclass && existing_type.parent_type != parent
            existing_type = current_type.types[node.name] = ObjectType.new(node.name, parent) unless existing_type

            @type_scope.push existing_type
            node.body.accept self
            @type_scope.pop
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

            possible_functions = scope.functions[node.name]
            possible_functions.each { |x| type_function_prototype(x) unless x.is_prototype_typed }
            raise "No functions named #{node.name} found (searching in scope #{scope.class.name})!" if possible_functions.size == 0

            #TODO: Check overloading
            function = possible_functions.first

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
    end
end
