require 'spec_helper'

describe Lexer do
    def self.it_lexes(str, *tokens)
        it "lexes #{str}" do
            lex = Lexer.new str, "lexer_spec"
            tokens.each do |tok|
                parsed = lex.next_token
                expect(parsed.kind).to eq tok.first
                expect(parsed.value).to eq tok.last if tok.last != tok.first
            end
            expect(lex.next_token.is_eof?).to be_truthy
        end
    end

    it_lexes "true false", [:true], [:false]
    it_lexes "null", [:null]
    it_lexes "10", [:integer, "10"]

    it_lexes "0.3 .4 1.0", [:double, "0.3"], [:double, ".4"], [:double, "1.0"]
    it_lexes "0.3.4", [:double, "0.3"], [:double, ".4"]

    it_lexes "'test'", [:string]
    it_lexes "\"test\"", [:string]

    ["def", "if", "elseif", "else", "for", "return", "new", "var", "class"].each do |kw|
        it_lexes kw, [:keyword, kw]
    end

    it_lexes "(){}[]", [:lparen], [:rparen], [:begin_block], [:end_block], [:special, "["], [:special, "]"]

    ["+", "-", "*", "/", "&&", "||", "and", "or", "==", "=", "!=", "<", "<=", ">", ">="].each do |op|
        it_lexes "10 #{op} 10", [:integer, "10"], [:operator, op], [:integer, "10"]
    end

    it_lexes "Test", [:constant]
    it_lexes "_test", [:identifier]

    it_lexes ":::", [:special, "::"], [:special, ":"]
    it_lexes "===", [:operator, "=="], [:operator, "="]

    it "keeps track of line numbers" do
        lex = Lexer.new "10 \n 9 \n 8"
        expect(lex.next_token.line_num).to eq 1
        expect(lex.next_token.line_num).to eq 2
        expect(lex.next_token.line_num).to eq 3
    end
end
