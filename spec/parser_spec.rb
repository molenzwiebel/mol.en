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
        it_errors_on "3 #{op}", /Expected expression at right hand side/
    end

    it_parses "a.b", MemberAccess.new("a".ident, "b".ident)
    it_parses "a.b.c", MemberAccess.new(MemberAccess.new("a".ident, "b".ident), "c".ident)
    it_parses "a.b()", Call.new("a".ident, "b", [])
    it_parses "a.b().c()", Call.new(Call.new("a".ident, "b", []), "c", [])
    it_errors_on "a.", /Expected identifier or call after/
    it_errors_on "a.new Bla()", /Expected identifier or call after/

    it_parses "def test(a: Int) -> Int 10", Function.new(nil, "test", "Int", [FunctionArg.new("a", "Int")], Body.from(Return.new(10.literal)))
    it_parses "def test() -> Int 10", Function.new(nil, "test", "Int", [], Body.from(Return.new(10.literal)))
    it_parses "def test(a: Int) 10", Function.new(nil, "test", nil, [FunctionArg.new("a", "Int")], Body.from(Return.new(10.literal)))
    it_parses "def test() 10", Function.new(nil, "test", nil, [], Body.from(Return.new(10.literal)))
    it_parses "def test() {}", Function.new(nil, "test", nil, [], nil)
    it_parses "def test() { 10 }", Function.new(nil, "test", nil, [], Body.from(Return.new(10.literal)))

    it_parses "if (true) 10", If.new(true.literal, Body.from(10.literal), nil, [])
    it_parses "if (true) 10 else 11", If.new(true.literal, Body.from(10.literal), Body.from(11.literal), [])
    it_parses "if (true) 10 elseif (false) 11", If.new(true.literal, Body.from(10.literal), nil, [[false.literal, Body.from(11.literal)]])
    it_parses "if (true) 10 elseif (false) 11 else 12",  If.new(true.literal, Body.from(10.literal), Body.from(12.literal), [[false.literal, Body.from(11.literal)]])
    it_errors_on "if (true) 10 else 11 else 12", /Multiple else blocks in if statement/
    it_errors_on "if true", /Expected token of type LPAREN/
    it_errors_on "if (true", /Expected token of type RPAREN/
    it_errors_on "if ()", /Expected condition/
end
