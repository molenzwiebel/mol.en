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
            body = Body.from(contents, true)
            body.accept visitor

            expect(body.type.name).to eq type if type
            expect(body.type).to eq nil unless type
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

    type "10", "int"
    type "3.2", "double"
    type "true", "bool"
    type "'test'", "str"

    type "var x = 10 x", "int"
    type "var x: String x", "String"
    type "var x = 12 x = 10", "int"
    type "var x= 12 x = 10 x", "int"

    type "new Integer", "Integer"
    type "return 10", "int"

    type "10 + 10", "int"
    type "10 - 10", "int"
    type "10 / 10", "int"
    type "10 * 10", "int"

    type "10.2 + 10", "double"
    type "10.2 - 10", "double"
    type "10.2 / 10", "double"
    type "10.2 * 10", "double"

    type "true && false", "bool"
    type "true || false", "bool"
    type "true and false", "bool"
    type "true or false", "bool"
    type "true == false", "bool"
    type "true != false", "bool"

    type "class Foo { var bar: int } var x = new Foo x.bar", "int"
    type "class Foo { var bar: int } var x = new Foo x.bar = 10", "int"
    type "class Foo { var bar: int } class Bar { var baz: Foo } var x = new Bar x.baz.bar = 10", "int"

    type "class Foo { var bar: int def get_bar() -> int this.bar } var x = new Foo x.get_bar()", "int"
    type "class Foo { var bar: int def get_bar() -> int bar } var x = new Foo x.get_bar()", "int"
    type "class Foo { var bar: int def set_bar(val: int) bar = val } var x = new Foo x.set_bar(10) x.bar", "int"
    type "class Foo { var bar: int def do_stuff() -> double { var bar = 10.0 bar } } new Foo.do_stuff()", "double"

    type "class Foo { def get_bar() -> int 42 } class Bar :: Foo { } new Bar.get_bar()", "int"

    fail_on "class Foo { var bar: int } var x = new Foo x.bar = 10.0", /Cannot assign/
    fail_on "class Foo { var bar: int } var x = new Foo x.baz", /Unknown member/

    fail_on "true * 10", /No function with/

    # Recursion :)
    type "def x() -> int x() x()", "int"

    type "def x() x() x()", nil
    type "def do_stuff() putchar(10) do_stuff()", nil

    type "def x() -> int 10 x()", "int"
    type "def x(a: double) -> double 1.3 x(1.2)", "double"
    type "def x(a: double) -> double a x(3.3)", "double"
    type "class int { def foo() -> int 10 } 10.foo()", "int"
    type "class int { def foo() -> int 10 } 10.foo().foo()", "int"
    type "class int { def get() -> int this } 10.get()", "int"

    type "def x(a: Object) -> int 10 x(new String('test'))", "int"
    fail_on "def x(a: String) -> int 10 x(3)", /No function with name 'x'/
    fail_on "def x() -> int 1.2", /Cannot return a /
    fail_on "def x(a: double) -> int a", /Cannot return a /
    fail_on "a(3)", /No function with name 'a'/
    fail_on "def x(a: String) -> int 10 x()", /No function with name 'x'/

    fail_on "var x: String = 12", /Conflicting types/
    fail_on "var x = 'test' x = 4", /Cannot assign/

    type "var x = 10 if (true) { x = 5 } x", "int"
    fail_on "if (true) { var x = 4 } x", /Undefined/

    type "def x() -> int if (true) return 10 else return 4 x()", "int"
    fail_on "def x() -> int if (true) 10", /may not return a value/
    fail_on "def x() -> int if (true) return 10 else 4", /may not return/
    fail_on "def x() -> int if (true) return 10 else return 4 elseif (false) 4", /may not return/
    fail_on "if (10) true else false", /Expected condition in if/
end