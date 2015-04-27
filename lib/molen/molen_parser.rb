
module Molen
    # Alias for create_parser that allows you to call
    # it when including the Molen module.
    def create_parser(source, file)
        Molen.create_parser source, file
    end

    # Creates and populates a new parser with all the
    # parsing rules required for parsing a mol.en src.
    def self.create_parser(source, file)
        Parser.new(source, file) do
            expr -> tok { tok.is_true? or tok.is_false? } do
                Bool.new consume.value == "true"
            end

            expr -> tok { tok.is_null? } do
                next_token; Null.new
            end

            expr -> tok { tok.is_integer? } do
                Int.new consume.value.to_i
            end

            expr -> tok { tok.is_double? } do
                Double.new consume.value.to_f
            end

            expr -> tok { tok.is_string? } do
                Str.new consume.value.gsub(/\\"/, "\"").gsub(/\\'/, "'").gsub(/^"|"$/, "").gsub(/^'|'$/, '')
            end

            expr -> tok { tok.is_identifier? } do
                name = consume.value
                if token.is_lparen? then
                    next Call.new nil, name, parse_delimited { |parser| parser.parse_expression }
                end
                Identifier.new name
            end

            expr -> tok { tok.is_constant? } do
                Constant.new consume.value
            end
        end
    end

    # We open up Parser here to add some functions that don't really
    # need to be in the parser class, but are still handy to use from
    # our parsing blocks.
    class Parser
        def parse_delimited(start_tok = "(", delim = ",", end_tok = ")")
            expect start_tok
            next_token # Consume start token

            ret = []
            until token.is? end_tok
                raise_error("Unexpected EOF", token) if token.is_eof?
                ret << yield(self)

                cor = token.is?(delim) || token.is?(end_tok)
                raise_error "Expected '#{delim}' or '#{end_tok}' in delimited list, received '#{token.value}'", token unless cor
                next_token if token.is? delim
            end
            next_token # Consume end token

            ret
        end
    end
end
