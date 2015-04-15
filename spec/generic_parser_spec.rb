require File.expand_path("../../lib/molen",  __FILE__)
include Molen

describe Parser do
    it "can parse a simple expression" do
        parser = Parser.new "true"
        parser.expr -> x { x.is_kind? :true } do
            next_token # Consume true
            true
        end

        expect(parser.parse_node).to eq(true)
    end

    it "can parse multiple expressions after each other" do
        parser = Parser.new "true 3.032"

        parser.expr -> x { x.is_kind? :true } do
            next_token # Consume true
            true
        end
        parser.expr -> x { x.is_kind? :double } do
            consume.value.to_f # Consume and return the value
        end

        expect(parser.parse_node).to eq true
        expect(parser.parse_node).to eq 3.032
    end

    it "can parse a simple statement" do
        parser = Parser.new "if { true }"

        parser.expr -> x { x.is_kind? :true } do
            next_token # Consume true
            true
        end
        parser.stmt -> x { x.is_keyword? "if" } do
            next_token # Consume 'if'
            raise "Expected { after if" unless token.is_kind? :begin_block
            next_token # Consume {
            body = parse_expression # Parse a simple expression
            raise "Expected } after if body" unless token.is_kind? :end_block 
            next_token # Consume }

            body
        end

        expect(parser.parse_node).to eq true
    end

    it "returns nil if something cannot be parsed" do
        parser = Parser.new "true false"
        parser.expr -> x { x.is_kind? :true } do
            next_token # Consume true
            true
        end

        expect(parser.parse_node).to eq true
        expect(parser.parse_node).to eq nil
    end

    it "handles precedence successfully" do
        parser = Parser.new "2 + 4 * 3"

        parser.expr -> x { x.is_kind? :integer } do
            consume.value.to_i
        end
        parser.infix 10, -> x { x.is_operator? "+" } do |left|
            next_token # Consume +
            "(#{left} + #{parse_expression 10})"
        end
        parser.infix 20, -> x { x.is_operator? "*" } do |left|
            next_token # Consume +
            "(#{left} * #{parse_expression 20})"
        end

        expect(parser.parse_node).to eq "(2 + (4 * 3))"
    end
end