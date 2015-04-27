require 'spec_helper'

describe Parser do
    def self.it_parses(src, compare_to)
        it "parses #{src}" do
            parser = Molen.create_parser src, "parser_spec"
            expect(parser.parse_node).to eq compare_to
        end
    end

    def self.it_errors_on(src, msg)
        it "prints a descriptive error message when trying to parse #{src}" do
            parser = Molen.create_parser src, "parser_spec"
            expect {
                parser.parse_node
            }.to raise_error msg
        end
    end

    it_parses "10", 10.literal
    it_parses "10.3", 10.3.literal
    it_parses "true", true.literal
    it_parses "false", false.literal
    it_parses "null", nil.literal
    it_parses "'test'", "test".literal
    it_parses "\"test\"", "test".literal
    it_parses "__var", "__var".ident
    it_parses "Var", "Var".const

    it_parses "(10)", 10.literal
    it_errors_on "()", /Expected node in parenthesized expression/
    it_errors_on "(test", /Expected token of type RPAREN/

    it_parses "test(10, 11)", Call.new(nil, "test", [10.literal, 11.literal])
    it_parses "new Test", New.new("Test".const, [])
    it_parses "new Test()", New.new("Test".const, [])
    it_parses "new Test(10, 11)", New.new("Test".const, [10.literal, 11.literal])
    it_errors_on "new test()", /Expected token of type CONSTANT/

    Molen::OPERATOR_NAMES.each do |op, name|
        it_parses "3 #{op} 3", Call.new(3.literal, name, [3.literal])
    end
end
