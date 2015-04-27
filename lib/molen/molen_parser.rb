
module Molen
    OPERATOR_NAMES = {
        "+"         => "__add",
        "-"         => "__sub",
        "*"         => "__mul",
        "/"         => "__div",
        "=="        => "__eq",
        "!="        => "__neq",
        "&&"        => "__and",
        "and"       => "__and",
        "||"        => "__or",
        "or"        => "__or",
        "<"         => "__lt",
        "<="        => "__lte",
        ">"         => "__gt",
        ">="        => "__gte"
    }

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

            expr -> tok { tok.is_keyword? "new" } do
                expect_next :constant
                name = token.value
                args = !next_token.is?("(") ? [] : parse_delimited { |parser| parser.parse_expression }
                New.new Constant.new(name), args
            end

            expr -> tok { tok.is_lparen? } do
                next_token # Consume (
                node = parse_node
                raise_error "Expected node in parenthesized expression", token unless node
                expect :rparen
                next_token # Consume )
                node
            end

            infix 11, -> x { x.is_operator? "+" }, &create_binary_parser(11)
            infix 11, -> x { x.is_operator? "-" }, &create_binary_parser(11)
            infix 12, -> x { x.is_operator? "*" }, &create_binary_parser(12)
            infix 12, -> x { x.is_operator? "/" }, &create_binary_parser(12)

            infix 4, -> x { x.is_operator?("&&") or x.is_operator?("and") }, &create_binary_parser(4)
            infix 3, -> x { x.is_operator?("||") or x.is_operator?("or")  }, &create_binary_parser(3)
            infix 9, -> x { x.is_operator? "<"  }, &create_binary_parser(9)
            infix 9, -> x { x.is_operator? "<=" }, &create_binary_parser(9)
            infix 9, -> x { x.is_operator? ">"  }, &create_binary_parser(9)
            infix 9, -> x { x.is_operator? ">=" }, &create_binary_parser(9)

            infix 8, -> x { x.is_operator? "==" }, &create_binary_parser(8)
            infix 8, -> x { x.is_operator? "!=" }, &create_binary_parser(8)

            infix 50, -> x { x.is? "." } do |left|
                next_token # Consume .
                right = parse_expression 50
                raise_error "Expected identifier or call after '.'", token unless right.is_a?(Call) or right.is_a?(Identifier)

                next Call.new left, right.name, right.args if right.is_a? Call
                next MemberAccess.new left, right
            end

            stmt -> x { x.is_keyword? "def" } do
                name = expect_next_and_consume(:identifier).value

                args = parse_delimited do |parser|
                    n = parser.expect(:identifier).value
                    parser.expect_next(":")
                    type = parser.expect_next_and_consume(:constant).value
                    FunctionArg.new n, type
                end
                type = nil
                if token.is? "->" then
                    expect_next(:constant)
                    type = consume.value
                end
                Function.new nil, name, type, args, parse_body
            end

            stmt -> x { x.is_keyword? "if" } do
                expect_next_and_consume(:lparen)
                cond = parse_expression
                raise_error "Expected condition in if statement", token unless cond
                expect_and_consume(:rparen)

                if_then = parse_body false
                else_ifs = []
                if_else = nil

                while token.is_keyword? "else" or token.is_keyword? "elseif"
                    raise_error "Multiple else blocks in if statement", token if token.is_keyword? "else" and if_else
                    if consume.is_keyword? "else" then
                        if_else = parse_body false
                    else
                        expect_and_consume(:lparen)
                        elseif_cond = parse_expression
                        raise_error "Expected condition in elseif statement", token unless cond
                        expect_and_consume(:rparen)

                        else_ifs << [elseif_cond, parse_body(false)]
                    end
                end

                If.new cond, if_then, if_else, else_ifs
            end

            stmt -> x { x.is_keyword? "for" } do
                expect_next_and_consume(:lparen)
                init = parse_node
                expect_and_consume(",")
                cond = parse_expression
                raise_error "Expected condition in for loop", token unless cond
                expect_and_consume(",")
                step = parse_node
                expect_and_consume(:rparen)

                For.new init, cond, step, parse_body(false)
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

        def create_binary_parser(prec, right_associative = false)
            return lambda do |left|
                op_tok = consume # Consume operator
                right = parse_expression right_associative ? prec - 1 : prec
                raise_error "Expected expression at right hand side of #{op_tok.value}", op_tok unless right
                return Call.new(left, OPERATOR_NAMES[op_tok.value], [right])
            end
        end

        def parse_body(auto_return = true)
            unless token.is_begin_block?
                node = parse_node
                raise_error "Expected node in body. Did you forget '{'?", token unless node
                node = Return.new(node) if node.is_a?(Expression) and auto_return
                return Body.from node
            end

            expect(:begin_block)
            next_token # Consume {

            contents = []
            until token.is_end_block?
                raise_error("Unexpected EOF", token) if token.is_eof?
                contents << parse_node
            end
            next_token # Consume }

            contents.push(Return.new(contents.pop)) if contents.size > 0 and contents.last.is_a?(Expression) and auto_return
            Body.from contents
        end
    end
end
