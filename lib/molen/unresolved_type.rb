
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
        def resolve(program)
            raise "Uninplemented UnresolvedType#resolve!"
        end
    end

    class UnresolvedVoidType < UnresolvedType
        def resolve(program)
            #TODO: program.types["void"]
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

        def resolve(program)
            type = program.types[name]
            raise "Undefined type '#{name}'!" unless type
            return type
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

        def resolve(program)
            #TODO: PointerType.new ptr_type.resolve(program)
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

        def resolve(program)
            # TODO
        end
    end
end
