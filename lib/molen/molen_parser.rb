
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
                parse_identifier
            end

            expr -> tok { tok.is_constant? } do
                parse_const
            end

            expr -> tok { tok.is? "@" } do
                next_token # Consume @
                right = parse_identifier
                raise_error "Expected call, identifier, assignment or member access after @, received #{right.inspect}", token unless right.is_a?(Call) || right.is_a?(Identifier) || right.is_a?(Assign) || right.is_a?(MemberAccess)

                next Call.new Identifier.new("this"), right.name, right.args, right.type_vars, right.block if right.is_a?(Call) && right.object.nil?
                next Call.new MemberAccess.new(Identifier.new("this"), right.object), right.name, right.args, right.type_vars, right.block if right.is_a?(Call)
                next Assign.new MemberAccess.new(Identifier.new("this"), right.target), right.value if right.is_a? Assign
                MemberAccess.new Identifier.new("this"), right
            end

            expr -> tok { tok.is? "[" } do
                NewArray.new parse_delimited("[", ",", "]") { parse_expression }
            end

            expr -> tok { tok.is? "!" } do
                next_token # Consume !
                Call.new parse_expression, "!", [], [], nil
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
                raise_error "Expected identifier or member access after &", token unless expr.is_a?(Identifier) or expr.is_a?(MemberAccess)
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

            expr -> tok { tok.is_keyword? "func" } do
                next_token

                ret_type = UnresolvedVoidType.new
                args = parse_delimited("(", ",", ")") do
                    name = expect_and_consume(:identifier).value
                    expect_and_consume(":")
                    FunctionArg.new name, parse_type
                end

                if token.is? "->" then
                    next_token # Consume ->
                    ret_type = parse_type
                end

                NewAnonymousFunction.new ret_type, args, parse_body(!ret_type.is_a?(UnresolvedVoidType))
            end

            infix 12, -> x { x.is_operator? "+" }, &create_binary_parser(12)
            infix 12, -> x { x.is_operator? "-" }, &create_binary_parser(12)
            infix 13, -> x { x.is_operator? "*" }, &create_binary_parser(13)
            infix 13, -> x { x.is_operator? "/" }, &create_binary_parser(13)
            infix 11, -> x { x.is_operator? "%" }, &create_binary_parser(11)

            infix 5, -> x { x.is_operator?("&&") or x.is_keyword?("and") }, &create_binary_parser(5)
            infix 4, -> x { x.is_operator?("||") or x.is_keyword?("or")  }, &create_binary_parser(4)
            infix 10, -> x { x.is_operator? "<"  }, &create_binary_parser(10)
            infix 10, -> x { x.is_operator? "<=" }, &create_binary_parser(10)
            infix 10, -> x { x.is_operator? ">"  }, &create_binary_parser(10)
            infix 10, -> x { x.is_operator? ">=" }, &create_binary_parser(10)

            infix 9, -> x { x.is_operator? "==" }, &create_binary_parser(9)
            infix 9, -> x { x.is_operator? "!=" }, &create_binary_parser(9)

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

            infix 2, -> x { x.is_is_a? } do |left|
                next_token
                IsA.new left, parse_type
            end

            infix 3, -> x { x.is_special? "`" } do |left|
                func_name = expect_next_and_consume(:identifier).value
                expect_and_consume "`"
                right = parse_expression 3
                raise_error "Expected expression at right hand side of `#{func_name}`", token unless right

                Call.new nil, func_name, [left, right], [], nil
            end

            infix 50, -> x { x.is? "." } do |left|
                next_token # Consume .
                right = parse_expression 50
                raise_error "Expected identifier or call after '.'", token unless right.is_a?(Call) or right.is_a?(Identifier)

                next Call.new left, right.name, right.args, right.type_vars, right.block if right.is_a? Call
                next MemberAccess.new left, right
            end

            stmt -> x { x.is_keyword? "def" } do
                next_token # Consume def
                is_static = false
                if token.is? "static" then
                    is_static = true
                    next_token # Consume static
                end

                type_vars = []
                type_vars = parse_delimited "<", ",", ">" do
                    parse_type
                end if token.is? "<"

                raise_error "Expected identifier or operator as function name", token unless token.is_identifier? or token.is_operator?
                name = consume.value

                args = parse_delimited do
                    n = expect_and_consume(:identifier).value
                    expect_and_consume(":")
                    FunctionArg.new n, parse_type
                end

                type = UnresolvedVoidType.new
                if token.is? "->" then
                    next_token # Consume ->
                    type = parse_type
                end

                Function.new name, is_static, type, args, type_vars, parse_body(!type.is_a?(UnresolvedVoidType))
            end

            stmt -> x { x.is_keyword? "if" } do
                expect_next_and_consume(:lparen)

                cond = parse_expression
                raise_error "Expected condition in if statement", token unless cond
                cond = Call.new(cond, "to_bool", [], [], nil)

                expect_and_consume(:rparen)

                then_body = parse_body false
                else_body = nil

                elseifs = []
                while token.is_keyword? "else" or token.is_keyword? "elseif"
                    raise_error "Multiple else blocks in if statement", token if token.is_keyword? "else" and else_body
                    if consume.is_keyword? "else" then
                        else_body = parse_body false
                    else
                        expect_and_consume(:lparen)

                        elseif_cond = parse_expression
                        raise_error "Expected condition in elseif statement", token unless elseif_cond
                        elseif_cond = Call.new(elseif_cond, "to_bool", [], [], nil)

                        expect_and_consume(:rparen)
                        elseifs << [elseif_cond, parse_body(false)]
                    end
                end

                elseifs.reverse_each do |else_if|
                    else_body = If.new else_if.first, else_if.last, else_body
                end

                If.new cond, then_body, else_body
            end

            stmt -> x { x.is_keyword? "for" } do
                expect_next_and_consume(:lparen)

                init = parse_node
                expect_and_consume(",")

                cond = parse_expression
                raise_error "Expected condition in for loop", token unless cond
                cond = Call.new(cond, "to_bool", [], [], nil)
                expect_and_consume(",")

                step = parse_node
                expect_and_consume(:rparen)

                For.new init, cond, step, parse_body(false)
            end

            stmt -> x { x.is_keyword? "return" } do
                next_token # Consume return
                Return.new parse_expression
            end

            stmt -> x { x.is_keyword? "var" } do
                name = expect_next_and_consume(:identifier).value
                expect_and_consume(":")
                VarDef.new name, parse_type
            end

            stmt -> x { x.is_keyword? "class" } do
                name = expect_next_and_consume(:constant).value
                parent = UnresolvedSimpleType.new ["Object"]
                type_vars = []

                if token.is? "<" then
                    type_vars = parse_delimited "<", ",", ">" do
                        parse_type
                    end
                end

                if token.is? "::" then
                    next_token # Consume ::
                    parent = parse_type
                end

                ClassDef.new(name, parent, type_vars, parse_body(false))
            end

            stmt -> x { x.is_keyword? "extern" } do
                name = expect_next_and_consume(:constant).value

                loc = nil
                if token.is? "(" then
                    loc = expect_next_and_consume(:string).value.gsub(/\\"/, "\"").gsub(/\\'/, "'").gsub(/^"|"$/, "").gsub(/^'|'$/, '')
                    expect_and_consume(")")
                end

                ExternalDef.new(name, loc, parse_body(false))
            end

            stmt -> x { x.is_keyword? "struct" } do
                name = expect_next_and_consume(:constant).value
                StructDef.new name, parse_body(false)
            end

            stmt -> x { x.is_keyword? "import" } do
                file = expect_next_and_consume(:string).value.gsub(/\\"/, "\"").gsub(/\\'/, "'").gsub(/^"|"$/, "").gsub(/^'|'$/, '')
                Import.new file
            end

            stmt -> x { x.is_keyword? "fn" } do
                func_name = expect_next_and_consume(:identifier).value
                args = parse_delimited do
                    n = expect(:identifier).value
                    expect_next_and_consume(":")
                    FunctionArg.new n, parse_type
                end

                ret_type = UnresolvedVoidType.new

                if token.is? "->" then
                    next_token # Consume ->
                    ret_type = parse_type
                end

                ExternalFuncDef.new(func_name, ret_type, args)
            end

            stmt -> x { x.is_keyword? "module" } do
                name = expect_next_and_consume(:constant).value
                type_vars = []

                if token.is? "<" then
                    type_vars = parse_delimited "<", ",", ">" do
                        parse_type
                    end
                end

                ModuleDef.new(name, type_vars, parse_body(false))
            end

            stmt -> x { x.is_keyword? "include" } do
                next_token # Consume include
                Include.new parse_type
            end

            stmt -> x { x.is_keyword? "type" } do
                next_token # Consume type
                name = expect_and_consume(:constant).value

                expect_and_consume("::")

                TypeAliasDef.new name, parse_type
            end
        end
    end

    # We open up Parser here to add some functions that don't really
    # need to be in the parser class, but are still handy to use from
    # our parsing blocks.
    class Parser
        def parse_const
            names = [consume.value]
            while token.is? ":"
                next_token
                raise_error "Expected constant after :", token unless token.is_constant?
                names << consume.value
            end
            Constant.new names
        end

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

        def parse_identifier
            name = consume.value
            if token.is_lparen? || token.is?("[") then
                type_args = []
                type_args = parse_delimited "[", ",", "]" do
                    if token.is?("*") || token.is_constant? then
                        next parse_type
                    end
                    parse_expression
                end if token.is? "["

                if token.is?("(") then
                    raise_error "Expected only types in generic function call", token if type_args.reject{|x| x.is_a?(UnresolvedType)}.size > 0

                    args = parse_delimited { parse_expression }
                    if token.is?("|") || token.is?("{") then
                        block_args = []
                        if token.is?("|") then
                            block_args = parse_delimited "|", ",", "|" do
                                expect_and_consume(:identifier).value
                            end
                        end

                        return Call.new nil, name, args, type_args, CallBlock.new(block_args, parse_body(false))
                    end

                    return Call.new nil, name, args, type_args, nil
                end

                if token.is?("=") then
                    next_token # Consume =

                    right = parse_expression
                    raise_error "Expected value in array assignment", token unless right

                    return Call.new(Identifier.new(name), "__index_set", [type_args.first, right], [], nil)
                end

                return Call.new Identifier.new(name), "__index_get", [type_args.first], [], nil
            end
            Identifier.new name
        end

        def create_binary_parser(prec, right_associative = false)
            return lambda do |left|
                op_tok = consume # Consume operator
                right = parse_expression right_associative ? prec - 1 : prec
                raise_error "Expected expression at right hand side of #{op_tok.value}", op_tok unless right
                return Call.new(left, op_tok.value, [right], [], nil)
            end
        end

        def parse_body(auto_return = true)
            unless token.is_begin_block?
                node = parse_node
                raise_error "Expected node in body. Did you forget '{'?", token unless node
                node = Return.new(node) if node.is_a?(Expression) && auto_return
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

            contents.push(Return.new(contents.pop)) if contents.size > 0 && contents.last.is_a?(Expression) && auto_return
            Body.from contents
        end
    end
end
