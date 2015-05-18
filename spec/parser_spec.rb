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

    it_parses "true", true.literal
    it_parses "false", false.literal
    it_parses "null", nil.literal

    it_parses "10", 10.literal
    it_parses "10L", 10.long
    it_parses "10.2", 10.2.literal
    it_parses ".2", 0.2.literal
    it_parses "0", 0.literal

    it_parses "\"test\"", "test".literal
    it_parses "'test'", "test".literal
    it_parses "'\\n\\r'", "\n\r".literal

    it_parses "x", "x".ident
    it_parses "__foo", "__foo".ident
    it_parses "X", "X".const
    it_parses "Foo", "Foo".const
    it_parses "A:B:C", ["A", "B", "C"].const

    it_parses "@foo", "foo".var
    it_parses "@foo(a, b)", Call.new("this".ident, "foo", ["a".ident, "b".ident], [])

    it_parses "[1, 2, 3]", [1, 2, 3].map(&:literal).new

    it_parses "3 `foo` 3", Call.new(nil, "foo", [3.literal, 3.literal], [])

    it_parses "(10 - 2) * 3", Call.new(Call.new(10.literal, "-", [2.literal], []), "*", [3.literal], [])

    it_parses "&foo", "foo".ident.ptr

    it_parses "sizeof Int", SizeOf.new("Int".type)
    it_parses "sizeof *Int", SizeOf.new("Int".type.ptr)
    it_parses "sizeof Foo<A, B>", SizeOf.new(UnresolvedGenericType.new("Foo".type, ["A".type, "B".type]))

    it_parses "new Foo", New.new("Foo".type, [])
    it_parses "new Foo()", New.new("Foo".type, [])
    it_parses "new Foo(1, 2, 3)", New.new("Foo".type, [1.literal, 2.literal, 3.literal])
    it_parses "new A<B>(1)", New.new(UnresolvedGenericType.new("A".type, ["B".type]), [1.literal])

    ["+", "-", "*", "/", "%", "&&", "and", "||", "or", "<", "<=", ">", ">=", "==", "!="].each do |op|
        it_parses "3 #{op} 3", Call.new(3.literal, op, [3.literal], [])
    end

    it_parses "x = 3", Assign.new("x".ident, 3.literal)
    it_parses "X = 3", Assign.new("X".const, 3.literal)

    it_parses "x = func(a: Int) -> Int 10", Assign.new("x".ident, NewAnonymousFunction.new("Int".type, [FunctionArg.new("a", "Int".type)], 10.literal.return))

    it_parses "2 as Int", Cast.new(2.literal, "Int".type)
    it_parses "2 as *Int", Cast.new(2.literal, "Int".type.ptr)
    it_parses "2 as Foo<A, B>", Cast.new(2.literal, UnresolvedGenericType.new("Foo".type, ["A".type, "B".type]))

    it_parses "a.b", MemberAccess.new("a".ident, "b".ident)
    it_parses "a.b()", Call.new("a".ident, "b", [], [])
    it_parses "@a.b", MemberAccess.new("a".var, "b".ident)
    it_parses "new Foo.test()", Call.new(New.new("Foo".type, []), "test", [], [])

    it_parses "a[1]", Call.new("a".ident, "__index_get", [1.literal], [])
    it_parses "a[1] = 2", Call.new("a".ident, "__index_set", [1.literal, 2.literal], [])

    it_parses "test[Int](10)", Call.new(nil, "test", [10.literal], ["Int".type])
    it_parses "test.test[Int, Double](10)", Call.new("test".ident, "test", [10.literal], ["Int".type, "Double".type])

    it_parses "def foo() bar", Function.new("foo", false, nil.type, [], [], "bar".ident)
    it_parses "def foo(a: Int) bar", Function.new("foo", false, nil.type, [FunctionArg.new("a", "Int".type)], [], "bar".ident)
    it_parses "def foo(a: Int, b: Bool) bar", Function.new("foo", false, nil.type, [FunctionArg.new("a", "Int".type), FunctionArg.new("b", "Bool".type)], [], "bar".ident)
    it_parses "def foo() -> Int 10", Function.new("foo", false, "Int".type, [], [], 10.literal.return)
    it_parses "def foo(a: Int) -> Bool true", Function.new("foo", false, "Bool".type, [FunctionArg.new("a", "Int".type)], [], true.literal.return)
    it_parses "def static foo() bar", Function.new("foo", true, nil.type, [], [], "bar".ident)
    it_parses "def <A, B> foo() bar", Function.new("foo", false, nil.type, [], ["A".type, "B".type], "bar".ident)

    it_parses "if (true) 10", If.new(true.literal.to_bool_call, 10.literal, nil)
    it_parses "if (true) 10 else 11", If.new(true.literal.to_bool_call, 10.literal, 11.literal)
    it_parses "if (true) 10 elseif (false) 11 else 12", If.new(true.literal.to_bool_call, 10.literal, If.new(false.literal.to_bool_call, 11.literal, 12.literal))

    it_parses "for (a, b, c) 10", For.new("a".ident, "b".ident.to_bool_call, "c".ident, 10.literal)
    it_parses "for (, b, ) 10", For.new(nil, "b".ident.to_bool_call, nil, 10.literal)
    it_parses "for (a, b, ) 10", For.new("a".ident, "b".ident.to_bool_call, nil, 10.literal)
    it_parses "for (, b, c) 10", For.new(nil, "b".ident.to_bool_call, "c".ident, 10.literal)

    it_parses "return", Return.new(nil)
    it_parses "return 10", 10.literal.return

    it_parses "var x: Int", VarDef.new("x", "Int".type)
    it_parses "var x: *Int", VarDef.new("x", "Int".type.ptr)

    it_parses "class X {}", ClassDef.new("X", "Object".type, [], [])
    it_parses "class X :: Super {}", ClassDef.new("X", "Super".type, [], [])
    it_parses "class X 10", ClassDef.new("X", "Object".type, [], 10.literal)
    it_parses "class X :: Super 10", ClassDef.new("X", "Super".type, [], 10.literal)

    it_parses "struct Foo {}", StructDef.new("Foo", [])
    it_parses "struct Foo { var x: Int }", StructDef.new("Foo", [VarDef.new("x", "Int".type)])

    it_parses "import 'foo'", Import.new("foo")
    it_parses "include Foo", Include.new("Foo".type)

    it_parses "module Foo {}", ModuleDef.new("Foo", [], [])
    it_parses "module Foo<X> {}", ModuleDef.new("Foo", ["X".type], [])

    it_parses "type Foo :: Int", TypeAliasDef.new("Foo", "Int".type)
end
