require File.expand_path("../../lib/molen",  __FILE__)
include Molen

describe Parser do
    def self.node(src, clazz = nil, other = nil)
        it "should be able to parse `#{src}` and return a #{clazz}" do
            parser = Molen::create_parser src
            node = parser.parse_node
            expect(node).to be_a clazz if clazz
            expect(node).to eq other if other
        end
    end

    def self.type(src, other)
        it "should be able to convert `#{src}` to a type" do
            parser = Molen::create_parser src
            type = Molen::parse_type parser
            expect(type).to eq other
        end
    end

    node "true", Bool, Bool.new("true")
    node "false", Bool, Bool.new("false")
    node "10", Int, Int.new(10)
    node "10.3", Double, Double.new(10.3)
    node "'test'", Str, Str.new("test")
    node "\"test\"", Str, Str.new("test")
    node "new MyClass(10)", New, New.new("MyClass", [Int.new(10)])
    node "(4 + 4) * 3", Binary, Binary.new("*", Binary.new("+", Int.new(4), Int.new(4)), Int.new(3))

    ["+", "-", "*", "/", "&&", "||", ">", ">=", "<", "<=", "==", "!=", "="].each do |op|
        node "3 #{op} 3", Binary, Binary.new(op, Int.new(3), Int.new(3))
    end

    node "test(10)", Call, Call.new("test", [Int.new(10)])

    node "def x(a: Boolean) 10", Function, Function.new("x", nil, [Arg.new("a", UnresolvedType.new("Boolean"))], Int.new(10))
    node "def x(a: Boolean) -> Int 10", Function, Function.new("x", UnresolvedType.new("Int"), [Arg.new("a", UnresolvedType.new("Boolean"))], Int.new(10))
    node "if (true) 10", If, If.new(Bool.new("true"), Int.new(10))
    node "if (true) 10 else 12", If, If.new(Bool.new("true"), Int.new(10), Int.new(12))
    node "if (true) 10 else 12 elseif (false) 14", If, If.new(Bool.new("true"), Int.new(10), Int.new(12), [[Bool.new("false"), Int.new(14)]])

    node "class Test :: Super { var x = 10 }", ClassDef, ClassDef.new("Test", "Super", [VarDef.new(Var.new("x"), nil, Int.new(10))], [])
    node "class Test :: Super { def test() return }", ClassDef, ClassDef.new("Test", "Super", [], [Function.new("test", nil, [], Return.new)])
    node "class Test :: Super { var x = 10 def test() return }", ClassDef, ClassDef.new("Test", "Super", [VarDef.new(Var.new("x"), nil, Int.new(10))], [Function.new("test", nil, [], Return.new)])

    node "for(3,2,1) 5", For, For.new(Int.new(2), Int.new(3), Int.new(1), Int.new(5))
    node "for(,2,1) 5", For, For.new(Int.new(2), nil, Int.new(1), Int.new(5))
    node "for(,2,) 5", For, For.new(Int.new(2), nil, nil, Int.new(5))
    node "return", Return, Return.new(nil)
    node "return 10", Return, Return.new(Int.new(10))
    node "var x = 10", VarDef, VarDef.new(Var.new("x"), nil, Int.new(10))
    node "var x: Int", VarDef, VarDef.new(Var.new("x"), UnresolvedType.new("Int"))
    node "var x: Int = 4", VarDef, VarDef.new(Var.new("x"), UnresolvedType.new("Int"), Int.new(4))
    node "a.b", Member, Member.new(Var.new("a"), Var.new("b"))
    node "a.b()", Call, Call.new("b", [], Var.new("a"))
    
    it "should error on undetermined types" do
        expect(lambda {
            parser = Molen::create_parser "var x"
            parser.parse_node
        }).to raise_error(RuntimeError)
    end

    type "String", UnresolvedType.new("String")
    type "String[]", UnresolvedArrayType.new(UnresolvedType.new("String"), -1)
    type "String[10]", UnresolvedArrayType.new(UnresolvedType.new("String"), 10)
    type "String[10][3]", UnresolvedArrayType.new(UnresolvedArrayType.new(UnresolvedType.new("String"), 10), 3)
    type "Int(String)", UnresolvedFunctionType.new([UnresolvedType.new("String")], UnresolvedType.new("Int"))
    type "Int(Int, Int)", UnresolvedFunctionType.new([UnresolvedType.new("Int"), UnresolvedType.new("Int")], UnresolvedType.new("Int"))
    type "Int(Int, Int(Int))", UnresolvedFunctionType.new([UnresolvedType.new("Int"), UnresolvedFunctionType.new([UnresolvedType.new("Int")], UnresolvedType.new("Int"))], UnresolvedType.new("Int"))
end