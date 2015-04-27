require 'spec_helper'

describe Parser do
    def self.it_parses(src, compare_to)
        it "parses #{src}" do
            parser = Molen.create_parser src, "parser_spec"
            expect(parser.parse_node).to eq compare_to
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

    it_parses "test(10, 11)", Call.new(nil, "test", [10.literal, 11.literal])
end
