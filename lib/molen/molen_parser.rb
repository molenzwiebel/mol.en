
module Molen
    def parse(src, name = "unknown_file")
        Molen.parse src, name
    end

    def self.parse(src, name = "unknown_file")
        parser = create_parser src, name
        contents = []
        while node = parser.parse_node
            contents << node
        end
        Body.from contents
    end

    def self.create_parser(source, file)
        Parser.new(source, file) do
            expr -> tok { tok.is_true? or tok.is_false? } do
                Bool.new consume.value == "true"
            end

            expr -> tok { tok.is_null? } do
                next_token; Null.new
            end

            expr -> tok { tok.is_integer? } do
                val = consume.value
                next Long.new val[0..-2].to_i if val[-1, 1] == "L"
                next Int.new val.to_i
            end

            expr -> tok { tok.is_double? } do
                Double.new consume.value.to_f
            end

            expr -> tok { tok.is_string? } do
                Str.new consume.value.gsub(/\\"/, "\"").gsub(/\\'/, "'").gsub(/^"|"$/, "").gsub(/^'|'$/, '').gsub(/\\n/, "\n").gsub(/\\r/, "\r")
            end

            expr -> tok { tok.is_identifier? } do
                name = consume.value
                if token.is_lparen? then
                    next Call.new nil, name, parse_delimited { parse_expression }
                end
                Identifier.new name
            end

            expr -> tok { tok.is_constant? } do
                Constant.new consume.value
            end

            expr -> tok { tok.is_instance_variable? } do
                name = consume.value[1..-1]
                if token.is_lparen? then
                    next Call.new(Identifier.new("this"), name, parse_delimited { parse_expression })
                end
                InstanceVariable.new name
            end

            expr -> tok { tok.is? "[" } do
                NewArray.new parse_delimited("[", ",", "]") { parse_expression }
            end

            expr -> tok { tok.is_lparen? } do
                next_token # Consume (
                node = parse_node
                raise_error "Expected node in parenthesized expression", token unless node
                expect_and_consume :rparen
                node
            end

            expr -> tok { tok.is? "&" } do
                next_token # Consume &
                expr = parse_expression
                raise_error "Expected identifier or instance variable after &", token unless expr.is_a?(Identifier) or expr.is_a?(InstanceVariable)
                PointerOf.new expr
            end

            expr -> tok { tok.is_keyword? "sizeof" } do
                next_token # Consume sizeof
                SizeOf.new parse_type
            end

            expr -> tok { tok.is_keyword? "new" } do
                expect_next :constant
                type = parse_type
                args = !token.is?("(") ? [] : parse_delimited { parse_expression }
                New.new type, args
            end

            infix 11, -> x { x.is_operator? "+" }, &create_binary_parser(11)
            infix 11, -> x { x.is_operator? "-" }, &create_binary_parser(11)
            infix 12, -> x { x.is_operator? "*" }, &create_binary_parser(12)
            infix 12, -> x { x.is_operator? "/" }, &create_binary_parser(12)
            infix 10, -> x { x.is_operator? "%" }, &create_binary_parser(10)

            infix 4, -> x { x.is_operator?("&&") or x.is_keyword?("and") }, &create_binary_parser(4)
            infix 3, -> x { x.is_operator?("||") or x.is_keyword?("or")  }, &create_binary_parser(3)
            infix 9, -> x { x.is_operator? "<"  }, &create_binary_parser(9)
            infix 9, -> x { x.is_operator? "<=" }, &create_binary_parser(9)
            infix 9, -> x { x.is_operator? ">"  }, &create_binary_parser(9)
            infix 9, -> x { x.is_operator? ">=" }, &create_binary_parser(9)

            infix 8, -> x { x.is_operator? "==" }, &create_binary_parser(8)
            infix 8, -> x { x.is_operator? "!=" }, &create_binary_parser(8)

            infix 1, -> x { x.is? "=" } do |left|
                next_token # Consume =
                right = parse_expression
                raise_error "Expected expression at right hand side of assignment", token unless right
                Assign.new left, right
            end

            infix 2, -> x { x.is_keyword? "as" } do |left|
                next_token
                Cast.new left, parse_type
            end

            infix 50, -> x { x.is? "." } do |left|
                next_token # Consume .
                right = parse_expression 50
                raise_error "Expected identifier or call after '.'", token unless right.is_a?(Call) or right.is_a?(Identifier)

                next Call.new left, right.name, right.args if right.is_a? Call
                next MemberAccess.new left, right
            end

            infix 25, -> x { x.is? "[" } do |left|
                next_token # Consume [
                ind = parse_expression
                raise_error "Expected indexing expression in []", token unless ind
                expect_and_consume "]"

                if token.is? "=" then
                    next_token # Consume =

                    right = parse_expression
                    raise_error "Expected value in array assignment", token unless right

                    next Call.new(left, "__index_set", [ind, right])
                end

                Call.new(left, "__index_get", [ind])
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
                ret << yield

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
                return Call.new(left, op_tok.value, [right])
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
