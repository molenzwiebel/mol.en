
# These are the "simple" types that come from the parser. They are converted to "actual" types
# when the code is generated.
module Molen
    def self.parse_type(parser, parse_ptr = true)
        simple = nil
        if parser.token.is_kind? :lparen then
            parser.next_token # Consume (
            type = parse_type(parser)
            raise "Expected parenthesized type to end with ')', received #{parser.token.kind} with value \"#{parser.token.value}\"" unless parser.token.is_kind? :rparen
            parser.next_token # Consume )
            simple = type
        end
        simple = UnresolvedType.new parser.consume.value unless simple
        while parser.token.is? "["
            tok = parser.next_token
            raise "Expected integer or ']' after TypeName[. Received #{parser.token.kind} with value \"#{parser.token.value}\"" if not tok.is? "]" and not tok.is_kind? :integer
            if tok.is? "]" then
                parser.next_token # Consume ]
                simple = ArrayType.new simple, -1
                next
            end
            parser.next_token # Consume num
            raise "Expected ']' after array dimension" if not parser.token.is? "]"
            parser.next_token # Consume ]
            simple = ArrayType.new simple, tok.value.to_i
        end
        return simple if (not parser.token.is? "," and not parser.token.is? "=>") or not parse_ptr
        in_types = [simple]
        while parser.token.is? ","
            parser.next_token # Consume ,
            in_types << parse_type(parser, false)
        end
        raise "Expected => after type list. Received #{parser.token.kind} with value \"#{parser.token.value}\"" unless parser.token.is? "=>"
        parser.next_token # Consume =>
        return FunctionType.new in_types, parse_type(parser)
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

    class VoidType < UnresolvedType
        def initialize
            super "void"
        end

        def ==(other)
            other.class == self.class
        end
    end

    class ArrayType < UnresolvedType
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

    class FunctionType < UnresolvedType
        attr_accessor :in_types, :out_type

        def initialize(t_in, t_out)
            super t_in.map(&:name).join(", ") + " => " + t_out.name
            @in_types = t_in
            @out_type = t_out
        end

        def ==(other)
            other.class == self.class && other.in_types == in_types && other.out_type == out_type
        end
    end
end