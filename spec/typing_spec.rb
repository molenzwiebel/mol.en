require File.expand_path("../../lib/molen",  __FILE__)
include Molen

describe TypingVisitor do
    def self.type(str, type)
        it "resolves the type of '#{str}' to be #{type}" do
            parser = Molen.create_parser str
            contents = []
            until (n = parser.parse_node).nil?
                contents << n
            end

            mod = Molen::Module.new
            visitor = TypingVisitor.new mod
            body = Body.from(contents)
            body.accept visitor

            expect(body.type.name).to eq type
        end
    end

    def self.fail_on(str, err)
        it "errors with resolving '#{str}'" do
            expect(lambda {
                parser = Molen.create_parser str
                contents = []
                until (n = parser.parse_node).nil?
                    contents << n
                end

                mod = Molen::Module.new
                visitor = TypingVisitor.new mod
                Body.from(contents).accept visitor
            }).to raise_error(RuntimeError, err)
        end
    end

    type "10", "Int"
    type "3.2", "Double"
    type "true", "Bool"
    type "'test'", "String"

    type "var x = 10", "Int"
    type "var x: String", "String"
    type "var x = 12 x = 10", "Int"
    type "var x= 12 x = 10 x", "Int"

    type "def x() -> Int 10 x()", "Int"
    type "def x(a: Double) -> Double 1.3 x(1.2)", "Double"
    type "def x(a: Double) -> Double a x(3.3)", "Double"
    type "class Int { def foo() -> Int 10 } 10.foo()", "Int"
    type "class Int { def foo() -> Int 10 } 10.foo().foo()", "Int"
    type "class Int { def get() -> Int this } 10.get()", "Int"
    fail_on "def x(a: String) -> Int 10 x(3)", /Cannot invoke function with argument types/
    fail_on "def x() -> Int 1.2", /Expected x to return a/
    fail_on "def x(a: Double) -> Int a", /Expected x to return a/
    fail_on "a(3)", /Undefined function/
    fail_on "def x(a: String) -> Int 10 x()", /Mismatched parameters/

    fail_on "var x: String = 12", /Conflicting types/
    fail_on "var x = 'test' x = 4", /Cannot assign/
end