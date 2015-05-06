require 'spec_helper'

describe GeneratingVisitor do
    def self.try_run(src, std = false)
        it "parses '#{src}' and generates without errors" do
            Molen.run src, "codegen_spec", std
        end
    end

    try_run "3"
    try_run "x = 3 x = 2 x"
    try_run "3.3"
    try_run "x = 31.2 x = 3.14 x"
    try_run "'test'"
    try_run "x = 'test' x = 'ok' x"

    try_run "def test() -> Int 10 test()"
    try_run "def test(x: Int) -> Int x test(10)"
    try_run "def test() 10 test()"
    try_run "def test(arg0: Int, arg1: Int) -> Int arg0 + arg1 test(1, 2)", true

    try_run "class X {} y = new X"
    try_run "class X { var foo: Int } y = new X"
    try_run "class X { var foo: Int def get_foo() -> Int this.foo } y = new X y.get_foo()"
end
