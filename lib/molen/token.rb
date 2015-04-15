
module Molen
    # This class represents a token. A token is a "significant" part in the processed
    # source code (for example a number, a string or '&&'). These tokens are then used
    # in the parser to figure out which ASTNodes they should represent.
    class Token
        # kind is a symbol indicating what kind this token is
        # value is the string containing the "value" of the token.
        # start_position is a fixnum which indicates at which index in the source this token started.
        # end_position is a fixnum indicating the end index of the token
        attr_reader :kind, :value, :start_position, :end_position

        def initialize(kind, value = "", start_pos = 0, end_pos = 0)
            @kind = kind
            @value = value
            @start_position = start_pos
            @end_position = end_pos
        end

        # Checks if this token is a operator with the specified value
        def is_operator?(val) 
            kind == :operator and value == val
        end

        # Checks if this token is a keyword with the specified value
        def is_keyword?(val)
            kind == :keyword and value == val
        end

        # Checks if this token indicates the end of the file
        def is_eof?
            kind == :eof
        end

        # Checks if this token is of the specified kind
        def is_kind?(kin)
            kind == kin
        end

        # Checks if the content of this token equals the given content
        def is?(val)
            value == val
        end

        def to_s
            "#<MolenLang::Token @value=\"#{value.to_s}\", @kind=:#{kind.to_s}, @start_index=#{start_index}, @end_index=#{end_index}>"
        end
    end
end