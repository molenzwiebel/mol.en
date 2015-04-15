require File.expand_path("../../lib/molen",  __FILE__)
include Molen

describe Lexer do
    def self.it_lexes(string, type, value = nil)
        it "lexes #{string}" do
            lexer = Lexer.new string
            tok = lexer.next_token
            expect(tok.kind).to  eq(type)
            expect(tok.value).to eq(value) if value
        end
    end

    def self.it_lexes_multiple(string, *args)
        it "lexes multiple tokens from #{string}" do
            lexer = Lexer.new string
            args.each do |kind_and_val|
                tok = lexer.next_token
                expect(tok.kind).to  eq(kind_and_val.first)
                expect(tok.value).to eq(kind_and_val.last) if kind_and_val.size == 2
            end
        end
    end

    it "should keep track of line numbers" do
        lexer = Lexer.new "4 \n \n 3 \n \n \n 33"
        expect(lexer.next_token.line).to eq 1
        expect(lexer.next_token.line).to eq 3
        expect(lexer.next_token.line).to eq 6
    end

    it_lexes "4", :integer
    it_lexes "4.0", :double
    it_lexes ".02", :double
    it_lexes "-.10", :double
    it_lexes ".02test", :double, ".02"
    it_lexes "'my string'", :string
    it_lexes "\"my string\"", :string

    it_lexes "true", :true
    it_lexes "false", :false
    it_lexes "null", :null

    it_lexes "defif", :keyword, "def"
    it_lexes "elseif", :keyword, "elseif"
    it_lexes "else if", :keyword, "else"
    it_lexes "___my_var__10___", :identifier

    it_lexes ":", :special, ":"
    it_lexes ":::", :special, "::"
    it_lexes_multiple ":::", [:special, "::"], [:special, ":"]

    it_lexes "=", :operator, "="
    it_lexes "===", :operator, "=="
    it_lexes_multiple "===", [:operator, "=="], [:operator, "="]

    it_lexes ">", :operator, ">"
    it_lexes ">=", :operator, ">="

    it_lexes_multiple "4 \n 'test'", [:integer], [:string]
    it_lexes_multiple "def test(a, b) {", [:keyword, "def"], [:identifier, "test"], [:lparen], [:identifier, "a"], [:special, ","], [:identifier, "b"], [:rparen], [:begin_block]
end