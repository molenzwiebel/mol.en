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

    it_types "new String[](10)", "String[]"
    it_types "new String[][](10)", "String[][]"
    it_fails_on "new Bla[](10)", /Undefined type 'Bla'/

    it_fails_on "[]", /Cannot deduce type of array: No initial elements or type given\./
    it_fails_on "[1, 3.3]", /Cannot deduce type of array: No common superclass found\./
    it_types "[10]", "Int[]"
    it_types "[10, 3, 4]", "Int[]"
    it_types "[[1,3], [3, 2]]", "Int[][]"
    it_types "class X {} class Y :: X {} [new X, new Y]", "X[]"
    it_types "class X {} class Y {} [new X, new Y]", "Object[]"

    it_types "x = [1, 2, 3] x[0]", "Int"
    it_types "x = [[1], [2]] x[0]", "Int[]"
    it_types "x = [[1], [2]] x[0][0]", "Int"
    it_types "x = [0, 2] x[0] = 1", "Int"
    it_fails_on "x = [1, 2] x[0] = 3.14", /No function with name '__index_set' \(on object of type Int\[\]\) and matching parameters found \(given Int, Double\)/
    it_fails_on "x = [1, 2] x[1.0] = 3", /No function with name '__index_set' \(on object of type Int\[\]\) and matching parameters found \(given Double, Int\)/
    it_fails_on "x = 3 x[3]", /No function with name '__index_get'/

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
    it_types "def test() -> Int[] new Int[]() test()", "Int[]"
    it_types "class Int { def test() -> Int this } 10.test()", "Int"

    it_types "class Test { static def get_int() -> Int 10 } Test.get_int()", "Int"
    it_types "class Test { static def func1() {} } class Test { static def func2() {} } Test.func1() Test.func2()", nil
    it_types "class Test { static def func1() {} static def func1(a: Int) {} } class Test { static def func2() {} } Test.func1() Test.func1(10) Test.func2()", nil

    it_types "extern C {}", "C"
    it_types "extern C('test') {}", "C"
    it_types "extern C { fn test() } C.test()", nil
    it_types "extern C { fn test(a: Int) } C.test(10)", nil
    it_types "extern C { fn test(a: Int) -> Int } C.test(10)", "Int"
    it_fails_on "extern C { fn test(a: Int) } C.test('hai')", /No function with name 'test'/
end
