require "spec_helper"

describe TypingVisitor do
    def self.it_types(str, name)
        it "types '#{str}'" do
            body = Molen.type Molen.parse(str, "typing_spec"), Program.new
            expect(body.contents.last.type).to be_nil unless name
            expect(body.contents.last.type.name).to eq name if name
        end
    end

    def self.it_fails_on(str, err)
        it "successfully deduces that '#{str}' is invalid" do
            body = Molen.parse(str, "typing_spec")
            vis = TypingVisitor.new Program.new
            expect {
                body.accept vis
            }.to raise_error err
        end
    end

    # Literals
    it_types "true", "Bool"
    it_types "10", "Int"
    it_types "10L", "Long"
    it_types "2.2", "Double"
    it_types "'test'", "String"

    # Variables and assigning
    it_types "x = 10", "Int"
    it_types "x = 10 x = 3", "Int"
    it_types "x = 3 x", "Int"
    it_fails_on "x = 3 x = true", /Cannot assign Bool to 'x'/

    # Functions and calls
    it_types "def foo() -> Int 10 foo()", "Int"
    it_types "def foo(a: Int) -> Int a foo(10)", "Int"
    it_types "def foo() -> Int 10 def foo(a: Int) -> Double 3.14 foo(10)", "Double"
    it_fails_on "foo()", /No function named foo with matching argument types found/

    # Member access
    it_types "class X { var foo: Int } new X.foo", "Int"
    it_types "struct X { var foo: Int } new X.foo", "Int"
    it_fails_on "10.foo", /Can only access members of objects and structs\. Tried to access foo on Int/

    # Assigning
    it_types "class X { var foo: Int } new X.foo = 10", "Int"
    it_types "struct X { var foo: Int } new X.foo = 10", "Int"

    # Sizeof
    it_types "sizeof Int", "Long"

    # Casting
    it_types "x = 10 x_ptr = &x x_ptr as *Double", "*Double"
    it_types "class X {} class Y :: X {} new X as Y", "Y"
    it_fails_on "class A {} class B {} new A as B", /Cannot cast A to B/

    # new
    it_types "class X {} new X", "X"
    it_types "struct X {} new X", "X"
    it_types "class X { class Y {} def static get() -> Y new Y } X.get()", "Y"

    # if, for
    it_types "if (true) {}", nil
    it_types "if (true) {} else {}", nil
    it_types "if (true) {} elseif (false) {} else {}", nil
    it_types "for(true, true, true) {}", nil
    it_types "for(, true, true) {}", nil
    it_types "for(true, true, ) {}", nil
    it_types "for(, true, ) {}", nil

    # Return
    it_fails_on "return 10", /Cannot return if not in a function/

    # Classdef
    it_types "class X {} X", "X:Metaclass"
end
