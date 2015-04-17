
# These are the "simple" types that come from the parser. They are converted to "actual" types
# when the code is generated.
module Molen
    def self.parse_type(parser)
        simple = UnresolvedType.new parser.consume.value unless simple
        while parser.token.is? "["
            tok = parser.next_token
            raise "Expected integer or ']' after TypeName[. Received #{parser.token.kind} with value \"#{parser.token.value}\"" if not tok.is? "]" and not tok.is_kind? :integer
            if tok.is? "]" then
                parser.next_token # Consume ]
                simple = UnresolvedArrayType.new simple, -1
                next
            end
            parser.next_token # Consume num
            raise "Expected ']' after array dimension" if not parser.token.is? "]"
            parser.next_token # Consume ]
            simple = UnresolvedArrayType.new simple, tok.value.to_i
        end
        return simple if not parser.token.is_kind? :lparen
        parser.next_token # Consume (
        arg_types = []
        until parser.token.is_kind? :rparen
            arg_types << parse_type(parser)
            raise "Expected ',' in function type arg list. Received #{parser.token.kind} with value \"#{parser.token.value}\"" unless parser.token.is? "," or parser.token.is_kind? :rparen
            parser.next_token if parser.token.is? ","
        end
        parser.next_token # Consume )
        return UnresolvedFunctionType.new arg_types, simple
    end

    class UnresolvedType
        attr_accessor :name

        def initialize(name)
            @name = name
        end

        def ==(other)
            other.class == self.class && other.name == name
        end
    end

    class UnresolvedVoidType < UnresolvedType
        def initialize
            super "void"
        end

        def ==(other)
            other.class == self.class
        end
    end

    class UnresolvedArrayType < UnresolvedType
        attr_accessor :type, :dim

        def initialize(type, dim = 0)
            super type.to_s + "[" + dim.to_s + "]"
            @type = type
            @dim = dim
        end

        def ==(other)
            other.class == self.class && other.type == type && other.dim == dim
        end
    end

    class UnresolvedFunctionType < UnresolvedType
        attr_accessor :in_types, :out_type

        def initialize(t_in, t_out)
            super t_out.name + "(" + t_in.map(&:name).join(", ") + ")"
            @in_types = t_in
            @out_type = t_out
        end

        def ==(other)
            other.class == self.class && other.in_types == in_types && other.out_type == out_type
        end
    end
end