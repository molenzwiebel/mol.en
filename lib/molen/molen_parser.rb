
module Molen
    def self.create_parser(source)
        parser = Parser.new source

        parser.expr -> tok { tok.is_kind? :true or tok.is_kind? :false } do
            Bool.new consume.value == "true"
        end
        parser.expr -> tok { tok.is_kind? :integer } do
            Int.new consume.value
        end
        parser.expr -> tok { tok.is_kind? :null } do
            next_token; Null.new
        end
        parser.expr -> tok { tok.is_kind? :double } do
            Double.new consume.value
        end
        parser.expr -> tok { tok.is_kind? :string } do
            Str.new consume.value.gsub(/\\"/, "\"").gsub(/\\'/, "'").gsub(/^"|"$/, "").gsub(/^'|'$/, '')
        end
        parser.expr -> tok { tok.is_kind? :identifier } do
            Var.new consume.value
        end 
        parser.expr -> tok { tok.is_keyword? "new" } do
            name = next_token.value
            args = next_token.is_kind?(:lparen) == false ? [] : Molen::parse_paren_list(self) do
                parse_expression
            end
            New.new name, args
        end
        parser.expr -> x { x.is_kind? :lparen} do
            next_token # Consume (
            node = parse_node
            raise "Expected node in parenthesized expression" unless node
            raise "Expected ')' after parenthesized expression, received #{token.kind} with value \"#{token.value.to_s}\"" unless token.is_kind? :rparen
            next_token # Consume )
            node
        end

        parser.infix 11, -> x { x.is_operator? "+" }, &create_binary_parser(11)
        parser.infix 11, -> x { x.is_operator? "-" }, &create_binary_parser(11)
        parser.infix 12, -> x { x.is_operator? "*" }, &create_binary_parser(12)
        parser.infix 12, -> x { x.is_operator? "/" }, &create_binary_parser(12)
        
        parser.infix 4, -> x { x.is_operator? "&&" }, &create_binary_parser(4)
        parser.infix 3, -> x { x.is_operator? "||" }, &create_binary_parser(3)
        parser.infix 9, -> x { x.is_operator? "<" },  &create_binary_parser(9)
        parser.infix 9, -> x { x.is_operator? "<=" }, &create_binary_parser(9)
        parser.infix 9, -> x { x.is_operator? ">" },  &create_binary_parser(9)
        parser.infix 9, -> x { x.is_operator? ">=" }, &create_binary_parser(9)
        
        parser.infix 8, -> x { x.is_operator? "==" }, &create_binary_parser(8)
        parser.infix 8, -> x { x.is_operator? "!=" }, &create_binary_parser(8)
        parser.infix 1, -> x { x.is_operator? "=" },  &create_binary_parser(11, true)

        parser.infix 50, -> x { x.is_kind? :lparen } do |left|
            args = Molen::parse_paren_list(self) do
                parse_expression
            end

            Call.new left, args
        end

        parser.stmt -> x { x.is_keyword? "def" } do
            name = next_token.value
            next_token # Consume name
            args = Molen::parse_paren_list(self) do
                n = :identifier.save >> ":" >> run
                [Var.new(n.value), Molen::parse_type(self)]
            end
            type = nil
            if token.is? "->" then
                next_token
                type = Molen::parse_type self
            end
            Function.new name, type, args, Molen::parse_body(self)
        end
        parser.stmt -> x { x.is_keyword? "if" } do
            next_token # Consume 'if'

            cond = :lparen >> expression.save >> :rparen >> run
            if_then = Molen::parse_body self, false
            else_ifs = []
            if_else = nil

            while token.is_keyword? "else" or token.is_keyword? "elseif"
                raise "Multiple else blocks in if statement." if token.is_keyword? "else" and if_else
                prev = consume # Consume keyword
                if prev.is_keyword? "else" then
                    if_else = Molen::parse_body self, false
                else
                    elsif_cond = :lparen >> expression.save >> :rparen >> run
                    else_ifs << [elsif_cond, Molen::parse_body(self, false)]
                end
            end

            If.new cond, if_then, if_else, else_ifs
        end
        parser.stmt -> x { x.is_keyword? "for" } do
            next_token # Consume 'for'
            init, cond, step = :lparen >> node.maybe.save >> "," >> expression.save >> "," >> node.maybe.save >> :rparen >> run

            body = Molen::parse_body self, false
            For.new cond, init, step, body
        end
        parser.stmt -> x { x.is_keyword? "return" } do
            next_token # Consume 'return'
            expr = parse_expression

            Return.new expr
        end
        parser.stmt -> x { x.is_keyword? "var" } do
            next_token # Consume 'var'

            name = :identifier.save >> run
            val = nil

            if token.is_operator? "=" then
                next_token # Consume =
                val = parse_expression
            end

            VarDef.new name.value, val
        end
        parser.stmt -> x { x.is_keyword? "class" } do
            next_token # Consume 'class'
            name, parent = :identifier.save >> ("::" >> :identifier).maybe.save >> :begin_block >> run
            vars = []
            funcs = []
            until token.is_kind? :end_block
                raise "Unexpected EOF" if token.is_eof?
                node = parse_node
                raise "Only variable declarations and functions allowed in class body." unless node.is_a? VarDef or node.is_a? Function
                vars << node if node.is_a? VarDef
                funcs << node if node.is_a? Function
            end
            next_token # Consume }

            ClassDef.new name.value, parent ? parent.value : nil, vars, funcs
        end

        parser
    end

    def self.create_binary_parser(prec, right_associative = false)
        return lambda do |left|
            op = consume.value # Consume operator
            right = parse_expression right_associative ? prec - 1 : prec
            return Binary.new op, left, right
        end
    end

    def self.parse_paren_list(parser, &block)
        raise "Expected ( in parenthesized list, received #{parser.token.kind} with value \"#{parser.token.value.to_s}\" instead." unless parser.token.is_kind? :lparen
        parser.next_token # Consume (

        ret = []
        until parser.token.is_kind? :rparen
            ret << parser.instance_exec(&block)
            raise "Expected ',' or ')' in argument list, received #{parser.token.kind} with value \"#{parser.token.value.to_s}\" instead." unless parser.token.is? "," or parser.token.is_kind? :rparen
            parser.next_token if parser.token.is? ","
        end
        parser.next_token # Consume )

        ret
    end

    def self.parse_body(parser, auto_return = true)
        unless parser.token.is_kind? :begin_block
            node = parser.parse_node
            raise "Expected an expression or statement in body. Did you forget '{'?" unless node
            return Body.from node # We don't require {} for a single statement or expression.
        end
        raise "Expected { at begin of body." unless parser.token.is_kind? :begin_block
        parser.next_token # Consume {

        contents = []
        until parser.token.is_kind? :end_block
            raise "Unexpected EOF" if parser.token.is_eof?
            contents << parser.parse_node
        end
        parser.next_token # Consume }

        if contents.last.is_a? Expression and auto_return then
            contents << ReturnStatement.new(contents.pop)
        end

        Body.from contents
    end

    class Parser
        ## Parsing helpers.
        def run(&block)
            Run.new block, self
        end

        def any_of(*args)
            Rule.new.any_of *args
        end

        def expression
            ExpressionParsingRule.new
        end

        def node
            ExpressionParsingRule.new
        end
    end
end