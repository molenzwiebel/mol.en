require 'spec_helper'

describe Parser do
    def self.it_parses(src, compare_to)
        it "parses '#{src}'" do
            parser = Molen.create_parser src, "parser_spec"
            expect(parser.parse_node).to eq compare_to
        end
    end

    def self.it_errors_on(src, msg)
        it "prints a descriptive error message when trying to parse '#{src}'" do
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
    it_parses "@test", "test".var
    it_parses "@__bla_322", "__bla_322".var

    it_parses "x[10]", Call.new("x".ident, "__index_get", [10.literal])
    it_parses "x[10][3]", Call.new(Call.new("x".ident, "__index_get", [10.literal]), "__index_get", [3.literal])
    it_parses "x[10] = 12", Call.new("x".ident, "__index_set", [10.literal, 12.literal])
    it_parses "x[10] = y = 12", Call.new("x".ident, "__index_set", [10.literal, Assign.new("y".ident, 12.literal)])

    it_parses "x = 10", Assign.new("x".ident, 10.literal)
    it_parses "return", Return.new(nil)
    it_parses "return 10", Return.new(10.literal)
    it_parses "var x: Int", InstanceVar.new("x", "Int")
    it_parses "var x: Int[]", InstanceVar.new("x", "Int[]")
    it_parses "var x: Int[][]", InstanceVar.new("x", "Int[][]")

    it_parses "var x: *Int", InstanceVar.new("x", "*Int")
    it_parses "var x: **Int", InstanceVar.new("x", "**Int")
    it_parses "var x: **Int[][]", InstanceVar.new("x", "**Int[][]")

    it_parses "&10", PointerOf.new(10.literal)
    it_parses "&(&10)", PointerOf.new(PointerOf.new(10.literal))
    it_errors_on "&", /Expected expression after &/

    it_parses "(10)", 10.literal
    it_errors_on "()", /Expected node in parenthesized expression/
    it_errors_on "(test", /Expected token of type RPAREN/

    it_parses "test(10, 11)", Call.new(nil, "test", [10.literal, 11.literal])
    it_parses "new Test", New.new("Test".const, [])
    it_parses "new Test()", New.new("Test".const, [])
    it_parses "new Test(10, 11)", New.new("Test".const, [10.literal, 11.literal])
    it_errors_on "new test()", /Expected token of type CONSTANT/

    it_parses "new Test[](10)", NewArray.new("Test[]", [10.literal])
    it_parses "new Test[]", NewArray.new("Test[]", [])

    it_parses "[1, 2, 3]", NewArray.new(nil, [1.literal, 2.literal, 3.literal])

    Molen::OPERATOR_NAMES.each do |op, name|
        it_parses "3 #{op} 3", Call.new(3.literal, name, [3.literal])
        it_errors_on "3 #{op}", /Expected expression at right hand side/
    end

    it_parses "a.b", MemberAccess.new("a".ident, "b".ident)
    it_parses "a.b.c", MemberAccess.new(MemberAccess.new("a".ident, "b".ident), "c".ident)
    it_parses "a.b()", Call.new("a".ident, "b", [])
    it_parses "A.b()", Call.new("A".const, "b", [])
    it_parses "A.b().c", MemberAccess.new(Call.new("A".const, "b", []), "c".ident)
    it_parses "a.b().c()", Call.new(Call.new("a".ident, "b", []), "c", [])
    it_errors_on "a.", /Expected identifier or call after/
    it_errors_on "a.new Bla()", /Expected identifier or call after/

    it_parses "def test(a: Int) -> Int 10", Function.new(nil, "test", "Int", [FunctionArg.new("a", "Int")], Body.from(Return.new(10.literal)))
    it_parses "def test() -> Int 10", Function.new(nil, "test", "Int", [], Body.from(Return.new(10.literal)))
    it_parses "def test(a: Int) 10", Function.new(nil, "test", nil, [FunctionArg.new("a", "Int")], Body.from(10.literal))
    it_parses "def test() 10", Function.new(nil, "test", nil, [], Body.from(10.literal))
    it_parses "def test() {}", Function.new(nil, "test", nil, [], nil)
    it_parses "def test() { 10 }", Function.new(nil, "test", nil, [], Body.from(10.literal))

    it_parses "def test(a: Int[], b: Bool[]) -> Int[] 10", Function.new(nil, "test", "Int[]", [FunctionArg.new("a", "Int[]"), FunctionArg.new("b", "Bool[]")], Body.from(Return.new(10.literal)))

    it_parses "if (true) 10", If.new(true.literal, Body.from(10.literal), nil, [])
    it_parses "if (true) 10 else 11", If.new(true.literal, Body.from(10.literal), Body.from(11.literal), [])
    it_parses "if (true) 10 elseif (false) 11", If.new(true.literal, Body.from(10.literal), nil, [[false.literal, Body.from(11.literal)]])
    it_parses "if (true) 10 elseif (false) 11 else 12",  If.new(true.literal, Body.from(10.literal), Body.from(12.literal), [[false.literal, Body.from(11.literal)]])
    it_errors_on "if (true) 10 else 11 else 12", /Multiple else blocks in if statement/
    it_errors_on "if true", /Expected token of type LPAREN/
    it_errors_on "if (true", /Expected token of type RPAREN/
    it_errors_on "if ()", /Expected condition/

    it_parses "for (true, true, true) 10", For.new(true.literal, true.literal, true.literal, 10.literal)
    it_parses "for (, true, true) 10", For.new(nil, true.literal, true.literal, 10.literal)
    it_parses "for (true, true, ) 10", For.new(true.literal, true.literal, nil, 10.literal)
    it_parses "for (, true, ) 10", For.new(nil, true.literal, nil, 10.literal)
    it_errors_on "for (,,) 10", /Expected condition in for loop/
    it_errors_on "for true", /Expected token of type LPAREN/
    it_errors_on "for (true 1)", /Expected token with value of ','/

    it_parses "class Test {}", ClassDef.new("Test", "Object", [], [], [])
    it_parses "class Test :: Super {}", ClassDef.new("Test", "Super", [], [], [])
    it_parses "class Test :: Super { var foo: Int }", ClassDef.new("Test", "Super", [InstanceVar.new("foo", "Int")], [], [])
    it_parses "class Test :: Super { def test() 10 }", ClassDef.new("Test", "Super", [], [Function.new(nil, "test", nil, [], 10.literal)], [])
    it_parses "class Test :: Super { static def test() 10 }", ClassDef.new("Test", "Super", [], [], [Function.new(nil, "test", nil, [], 10.literal)])

    it_parses "extern C {}", ExternalDef.new("C", nil, [])
    it_parses "extern C('test') {}", ExternalDef.new("C", "test", [])
    it_parses "extern C { fn test() }", ExternalDef.new("C", nil, [ExternalFunc.new(nil, "test", nil, [])])
    it_parses "extern C { fn test(a: Int) }", ExternalDef.new("C", nil, [ExternalFunc.new(nil, "test", nil, [FunctionArg.new("a", "Int")])])
    it_parses "extern C { fn test(a: Int) -> Int }", ExternalDef.new("C", nil, [ExternalFunc.new(nil, "test", "Int", [FunctionArg.new("a", "Int")])])

    it_parses "struct Foo {}", StructDef.new("Foo", [])
    it_parses "struct Foo { var x: Int }", StructDef.new("Foo", [InstanceVar.new("x", "Int")])
    it_parses "struct Foo { var x: Int var y: Double }", StructDef.new("Foo", [InstanceVar.new("x", "Int"), InstanceVar.new("y", "Double")])
end
