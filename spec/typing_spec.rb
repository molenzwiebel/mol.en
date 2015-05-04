require 'spec_helper'

describe TypingVisitor do
    def self.it_types(str, name)
        it "types '#{str}'" do
            body = Molen.parse(str, "typing_spec")
            vis = TypingVisitor.new Molen::Module.new
            body.accept vis
            expect(body.contents.last.type).to be_nil unless name
            expect(body.contents.last.type.name).to eq name if name
        end
    end

    def self.it_fails_on(str, err)
        it "successfully deduces that '#{str}' is invalid" do
            body = Molen.parse(str, "typing_spec")
            vis = TypingVisitor.new Molen::Module.new
            expect {
                body.accept vis
            }.to raise_error err
        end
    end

    it_types "10", "Int"
    it_types "3.3", "Double"
    it_types "true", "Bool"
    it_types "null", nil
    it_types "'test'", "String"

    it_types "x = 10", "Int"
    it_types "x = 10 x", "Int"
    it_fails_on "x = 10 for(,true,) { y = 5 } y", /Undefined variable 'y'/
    it_fails_on "x = 10 x = true", /Cannot assign Bool to 'x'/

    it_types "if (true) { 10 } else { 11 }", nil
    it_fails_on "if (10) {}", /Expected condition in if to be a boolean/

    it_types "for(,true,) { 10 }", nil
    it_fails_on "for (,10,) {}", /Expected condition in loop to be a boolean/

    it_fails_on "return 10", /Cannot return if not in a function!/
    it_fails_on "def x() -> Int return 3.3", /Cannot return value of type Double/
    it_fails_on "def x() -> Int return", /Cannot return void from/

    it_types "def test() -> Int 10 test()", "Int"
    it_types "def test() 10 test()", nil

    it_types "class X {} new X", "X"
    it_fails_on "new X", /Undefined type 'X'/
    it_fails_on "new Int", /Cannot instantiate primitive/

    it_types "class Test {}", "Test"
    it_fails_on "class Test :: Foo {}", /Class Foo \(superclass of Test\) not found!/

    it_types "class Test { var foo: Int } x = new Test() x.foo", "Int"
    it_types "class Test { var foo: Int } x = new Test() x.foo = 10", "Int"
    it_fails_on "class Test { var foo: Int } x = new Test() x.foo = 4.4", /Cannot assign Double to/

    it_fails_on "@test", /Cannot access instance variables if not in a function/
    it_fails_on "def test() @test", /Cannot access instance variables if not in a class function/
    it_fails_on "class X { def test() @test }", /Unknown instance variable test/
    it_types "class X { var foo: Int def get_foo() -> Int @foo } y = new X y.get_foo()", "Int"

    it_types "class X { var foo: Int def set_foo(x: Int) @foo = x } y = new X y.set_foo(12)", nil
    it_fails_on "class X { var foo: Int def set_foo(x: Double) @foo = x } y = new X y.set_foo(12.0)", /Cannot assign Double to/

    it_fails_on "def test() { if (true) { return } 10 }", /Unreachable code/
    it_fails_on "def test() { if (true) { return } else { return } 10 }", /Unreachable code/
    it_types "def test() { if (true) { return } else { } 10 }", nil

    it_types "def test() -> Int 10 def test(a: Int) -> Double 10.1 test()", "Int"
    it_types "def test() -> Int 10 def test(a: Int) -> Double 10.1 test(1)", "Double"
    it_types "class Int { def test() -> Int this } 10.test()", "Int"
end
