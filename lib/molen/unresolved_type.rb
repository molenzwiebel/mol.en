require "deep_clone"

module Molen
    class Parser
        def parse_type
            raise_error "Expected constant, * or ( when parsing type.", token unless token.is?("*") || token.is?("(") || token.is_constant?

            if token.is? "*" then
                next_token # Consume *
                return UnresolvedPointerType.new parse_type
            end

            if token.is? "(" then
                arg_types = parse_delimited { parse_type }
                ret_type = UnresolvedVoidType.new
                if token.is? "->" then
                    next_token
                    ret_type = parse_type
                end

                return UnresolvedFunctionType.new ret_type, arg_types
            end

            expect(:constant)
            simple = UnresolvedSimpleType.new parse_const.names
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
        attr_accessor :names

        def initialize(names)
            @names = names
        end

        def ==(other)
            other.is_a?(UnresolvedSimpleType) && other.names == names
        end

        def resolve(visitor)
            visitor.resolve_constant_type names
        end

        def to_s
            names.join ":"
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
            return nil unless type
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
        end

        def ==(other)
            other.class == self.class && other.base_type == base_type && other.type_args == type_args
        end

        def resolve(visitor)
            type = base_type.resolve(visitor)
            args = type_args.map { |e| e.resolve(visitor) }
            return nil if type.nil? || args.include?(nil)

            existing = visitor.resolve_constant_type ["#{type.name}<#{args.map(&:name).join(", ")}>"]
            return existing if existing

            if type.is_a?(ObjectType)
                new_type = ObjectType.new(type.name, type.parent_type, Hash[type.generic_types.keys.zip(args)])
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
                return new_type
            else
                new_type = ModuleType.new(type.name, {}, Hash[type.generic_types.keys.zip(args)])
                visitor.type_scope.last.types[new_type.name] = new_type
                visitor.type_scope.push new_type

                type.functions.each do |name, funcs|
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
                return new_type
            end
        end

        def to_s
            base_type.to_s + "<" + type_args.map(&:to_s).join(", ") + ">"
        end
    end

    class UnresolvedFunctionType < Type
        attr_accessor :return_type, :arg_types

        def initialize(return_type, arg_types)
            @return_type, @arg_types = return_type, arg_types
        end

        def resolve(visitor)
            ret_type = return_type.resolve(visitor)
            args = arg_types.map { |e| e.resolve(visitor) }
            return nil if ret_type.nil? || args.include?(nil)

            #TODO return FunctionType.new ret_type, args
            nil
        end

        def ==(other)
            other.class == self.class && other.return_type == return_type && other.arg_types == arg_types
        end

        def to_s
            ret = "(#{arg_types.map(&:to_s).join(", ")})"
            ret << " -> #{return_type.to_s}" unless return_type.is_a?(UnresolvedVoidType)
            ret
        end
    end
end
