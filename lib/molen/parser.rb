
module Molen
    # This is the parser for mol.en. It is responsible for taking our tokens and somehow
    # creating ASTNodes from them. The parser is as abstract as possible to allow a simple
    # set of predicate block + parsing block to actually dictate the parsing rules. Running
    # this parser on its own will do nothing.

    # It is important to keep in mind that @current_token is the token we are currently
    # looking at. When a parsing block is called, @current_token will correspond to the
    # token that caused the selection of that block. For example, @current_token will be
    # 'def' if the method parsing block is being executed.

    # A parsing block is responsible for consuming tokens and is expected to have
    # @current_token pointing to the next expression after the parsing. If we have the
    # source "3 + 3 'test'", @current_token should correspond to 'test' after the 3 + 3
    # expression has been parsed.

    # This parser runs all blocks using instance_exec so the parsing blocks have access
    # to methods such as `next_token` and `consume`. This makes for clearer and easier
    # parsing.

    # This parser is a Pratt parser and handles precedence fairly easy. To create an infix
    # that keeps precedence in mind, just call parse_expression with the precedence of the
    # current operator. If you want the operator to be right-associative, call it with
    # precedence - 1. A simple example for the '+' operator:

    # parser.infix(10, proc{|x| x.is_operator? "+"}) do |left_expression|
    #   next_token # Consume the '+'
    #   right_expression = parse_expression(10) # We defined 10 to be the precedence 2 lines up.
    #   return PlusExpression.new(left_expression, right_expression)
    # end
    class Parser
        def initialize(src, file = "src", &block)
            @source = src
            @file = file
            @lexer = Lexer.new src, file
            @current_token = @lexer.next_token

            @expression_parsers = {} #Predicate: Void -> Expression
            @statement_parsers  = {} #Predicate: Void -> Statement
            @infix_parsers      = {} #Predicate: [Precedence, Void -> Expression]

            instance_exec &block if block
        end

        # Gets the next token from the parser.
        def next_token
            @current_token = @lexer.next_token
        end

        # Returns which token we are currently looking at.
        def current_token
            @current_token
        end
        alias :token :current_token

        # "Consumes" the current token, returning it and advancing to the next token.
        def consume
            cur = @current_token
            next_token
            return cur
        end

        # Defines a new expression matcher. The first argument is a proc or lambda that
        # takes in a token and returns whether the parsing block should be executed. The
        # block argument is ran as the parser (using instance_exec) and should return the
        # parsed expression.
        def expr(matcher, &block)
            @expression_parsers[matcher] = block
        end

        # Defines a new statement matcher. The first argument is a proc or lambda that
        # takes in a token and returns whether the parsing block should be executed. The
        # block argument is ran as the parser (using instance_exec) and should return the
        # parsed statement.
        def stmt(matcher, &block)
            @statement_parsers[matcher] = block
        end

        # Defines an infix expression parser with the provided precedence. This method
        # is used for registering operators. The first argument is a proc or lambda that
        # takes in a token and returns whether the parsing block should be executed. The
        # block argument is ran as the parser (using instance_exec) with a single argument,
        # the left hand side of the infix. The parsing block is expected to return the parsed
        # expression.
        def infix(precedence, matcher, &block)
            @infix_parsers[matcher] = [precedence, block]
        end

        # Parses a node. This tries to parse an expression and when it fails resorts to a statement.
        # Returns nil when no node can be parsed.
        def parse_node
            expr = parse_expression
            return expr if expr

            stmt = parse_statement
            return stmt if stmt

            nil
        end

        # Parses a statement. Returns nil if no statements are able to be parsed
        def parse_statement
            ret, line = nil, current_token.line_num
            @statement_parsers.each do |matcher, parser|
                next unless matcher.call(current_token) && ret.nil?
                ret = instance_exec(&parser)
            end
            if ret then
                add_line_info(line, ret)
            end
            ret
        end

        # Parses an expression, optionally providing the precedence. This method
        # keeps in mind the precedence as described at the top of this file.
        # Returns nil when there is no expression to be parsed.
        def parse_expression(precedence = 0)
            ret, line = nil, current_token.line_num
            @expression_parsers.each do |matcher, parser|
                next unless matcher.call(current_token) && ret.nil?

                left = instance_exec &parser
                while precedence < cur_token_precedence
                    _, contents = @infix_parsers.select{|key, val| key.call @current_token}.first
                    left = instance_exec left, &contents.last
                end
                ret = left
            end
            if ret then
                add_line_info(line, ret)
            end
            ret
        end

        # Checks if the current token is of the specified kind and value,
        # and raises an error when this is not the case.
        def expect(one, two = nil)
            tok = token
            check_eq tok, one, two
        end

        def expect_and_consume(one, two = nil)
            ret = expect one, two
            next_token
            return ret
        end

        # Checks if the next token is of the specified kind and value,
        # and raises an error when this is not the case.
        def expect_next(one, two = nil)
            tok = next_token
            check_eq tok, one, two
        end

        def expect_next_and_consume(one, two = nil)
            ret = expect_next one, two
            next_token
            return ret
        end

        # Helper method for expect and expect_next that compares a token
        # and composes an error message when they are not equal.
        def check_eq(tok, one, two)
            one_matches = one.is_a?(Symbol) ? tok.is_kind?(one) : tok.is?(one)
            two_matches = two ? two.is_a?(Symbol) ? tok.is_kind?(two) : tok.is?(two) : true
            return tok if one_matches and two_matches

            type = one.is_a?(Symbol) ? one : two.is_a?(Symbol) ? two : nil
            val = one.is_a?(String) ? one : two.is_a?(String) ? two : nil

            err_msg = "Expected token"
            err_msg << " of type #{type.to_s.upcase}" if type
            err_msg << " with value of '#{val.to_s}'" if val
            err_msg << ", received a #{tok.kind.upcase} with value '#{tok.value.to_s}'"
            raise_error err_msg, tok
        end

        # Creates and raises a neatly formatted error message that indicates
        # the location and surroundings of the error. Line, col and length
        # are used for the fancy indication of where the error lies and can
        # be easily gotten from a token (as seen in check_eq). You can also
        # pass in a token, in which case that token will be used for positioning.
        def raise_error(message, line, col = 0, length = 0)
            line, col, length = line.line_num, line.column, line.length if line.is_a? Token

            header = "#{@file}##{line}: "
            str = "Error: #{message}\n".red
            str << "#{@file}##{line - 1}: #{@source.lines[line - 2].chomp}\n".light_black if line > 1
            str << "#{header}#{(@source.lines[line - 1] || "").chomp}\n"
            str << (' ' * (col + header.length - 1))
            str << '^' << ('~' * (length - 1)) << "\n"
            str << "#{@file}##{line + 1}: #{@source.lines[line].chomp}\n".light_black if @source.lines[line]
            raise str
        end

        private
        # Helper method that finds the precedence for the current token, or 0 if the
        # current token is not a valid infix token.
        def cur_token_precedence
            filtered = @infix_parsers.select{|key, val| key.call @current_token}
            return 0 if filtered.size == 0
            _, contents = filtered.first
            contents[0]
        end

        def add_line_info(line, node)
            return if node.is_a?(Body)
            return unless node.is_a?(ASTNode) || node.is_a?(::Enumerable)

            if node.is_a?(::Enumerable) then
                node.each {|el| add_line_info(line, el)}
            else
                node.line = line
                node.filename = @file
                node.instance_variables.each do |var|
                    add_line_info(line, node.instance_variable_get(var))
                end
            end
        end
    end
end
