require "deep_clone"

module Molen
    class Parser
        def parse_type
            raise_error "Expected constant or * when parsing type.", token unless token.is?("*") || token.is_constant?

            if token.is? "*" then
                next_token # Consume *
                return UnresolvedPointerType.new parse_type
            end

            simple = UnresolvedSimpleType.new expect_and_consume(:constant).value
            return simple unless token.is? "<"

            arg_types = parse_delimited "<", ",", ">" do
                parse_type
            end

            return UnresolvedGenericType.new simple, arg_types
        end
    end

    # An unresolved type is a type that is given by the
    # user but not yet converted into a type that the
    # codegen can understand. These types will be converted
    # to normal types as part of the typing and validating.
    class UnresolvedType
        def resolve(visitor)
            raise "Uninplemented UnresolvedType#resolve!"
        end
    end

    class UnresolvedVoidType < UnresolvedType
        def resolve(visitor)
            VoidType.new
        end

        def to_s
            "void"
        end

        def ==(other)
            other.class == self.class
        end
    end

    class UnresolvedSimpleType < UnresolvedType
        attr_accessor :name

        def initialize(name)
            @name = name
        end

        def ==(other)
            other.is_a?(UnresolvedSimpleType) && other.name == name
        end

        def resolve(visitor)
            type = nil

            visitor.type_scope.reverse_each do |scope|
                if !scope.is_a?(Program) && scope.name == name then
                    type = scope
                    break
                end
                type = scope.lookup_type(name) and break
            end

            type
        end

        def to_s
            name
        end
    end

    class UnresolvedPointerType < UnresolvedType
        attr_accessor :ptr_type

        def initialize(type)
            @ptr_type = type
        end

        def ==(other)
            other.class == self.class && other.ptr_type == ptr_type
        end

        def resolve(visitor)
            type = ptr_type.resolve(visitor)
            raise "Undefined type '#{ptr_type.to_s}'" unless type
            PointerType.new visitor.program, type
        end

        def to_s
            "*" + type.to_s
        end
    end

    class UnresolvedGenericType < UnresolvedType
        attr_accessor :base_type, :type_args

        def initialize(base_type, type_args)
            @base_type, @type_args = base_type, type_args
            @simple_generic_type = UnresolvedSimpleType.new base_type.to_s + "<" + type_args.map(&:to_s).join(",") + ">"
        end

        def ==(other)
            other.class == self.class && other.base_type == base_type && other.type_args == type_args
        end

        def resolve(visitor)
            existing = @simple_generic_type.resolve(visitor)
            return existing if existing

            type = base_type.resolve(visitor)
            args = type_args.map { |e| e.resolve(visitor) }
            return nil if type.nil? || args.include?(nil)

            new_type = ObjectType.new(type.name, nil, Hash[type.generic_types.keys.zip(args)])
            new_type.parents = type.parents
            visitor.type_scope.last.types[new_type.name] = new_type
            visitor.type_scope.push new_type

            type.vars.local_each do |name, var_type|
                var_type = var_type.resolve(visitor) if var_type.is_a?(UnresolvedType)
                new_type.vars[name] = var_type
            end

            type.functions.local_each do |name, funcs|
                funcs.each do |f|
                    # Prevent cloning of these two
                    f.type_scope = nil
                    f.owner_type = nil
                end
                new_funcs = DeepClone.clone(funcs)
                new_funcs.each do |func|
                    func.accept visitor
                end
            end

            visitor.type_scope.pop
            new_type
        end

        def to_s
            base_type.to_s + "<" + type_args.map(&:to_s).join(", ") + ">"
        end
    end
end
