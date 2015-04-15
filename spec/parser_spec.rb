require File.expand_path("../../lib/molen",  __FILE__)
include Molen

describe Parser do
    def self.node(src, clazz, other)
        it "should be able to parse `#{src}` and return a #{clazz}" do
            parser = Molen::create_parser src
            node = parser.parse_node
            expect(node).to be_a clazz
            expect(node).to eq other
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

    node "test(10)", Call, Call.new(Var.new("test"), [Int.new(10)])
    node "test(10)()", Call, Call.new(Call.new(Var.new("test"), [Int.new(10)]), [])

    node "def x(a) 10", Function, Function.new("x", ["a"], Int.new(10))
    node "if (true) 10", If, If.new(Bool.new("true"), Int.new(10))
    node "if (true) 10 else 12", If, If.new(Bool.new("true"), Int.new(10), Int.new(12))
    node "if (true) 10 else 12 elseif (false) 14", If, If.new(Bool.new("true"), Int.new(10), Int.new(12), [[Bool.new("false"), Int.new(14)]])

    node "for(3,2,1) 5", For, For.new(Int.new(2), Int.new(3), Int.new(1), Int.new(5))
    node "for(,2,1) 5", For, For.new(Int.new(2), nil, Int.new(1), Int.new(5))
    node "for(,2,) 5", For, For.new(Int.new(2), nil, nil, Int.new(5))
    node "return", Return, Return.new(nil)
    node "return 10", Return, Return.new(Int.new(10))
    node "var x = 10", VarDef, VarDef.new("x", Int.new(10))
end