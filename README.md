# Syntax ideas:

def functionName(a: TYPE, b: TYPE) -> TYPE {
    # Code here, implicit return
}

class Foo {
    CONSTANT = 10

    # No implicit accessors, there are only functions
    var a: TYPE
    var b: TYPE

    def init(a: TYPE, b: TYPE) {
        @a = b
        @b = a
    }

    # Allows you to use myFoo.foo = 10
    def foo=(a: TYPE) @a = a
    def foo @a

    def +(other: Foo) Foo.new(other.foo + @a)
}

# Alias the type. This simply gives it another name, casting will still
# work the normal way (you can cast Bar to Foo without problems).
type Bar = Foo

extern NameOfLibrary {
    fn myExternalCFunction(a: Int, b: NotAnInt) -> Char*
}

# Constraints define what kinds of types are allowed
constraint NeedsBla {
    def bla -> Foo
    def bla=(newVal: Foo) # Needs settable

    include Number # Needs to include number (have all number methods.)
}

# Any object that conforms to the constraint can be passed to this function.
def doSomethingWithSomethingThatHasBla(arg: NeedsBla) {
    puts arg.bla
}

# Structs behave exactly the same as classes, but are represented differently
# in the generated LLVM IR. Mostly used for externs.
struct Foo {}

# Variables can be assigned a value without previous declaration, but cannot be referenced before they get assigned a value
a = 10
b = a + 20

# Anon functions
myFunc = func(a: TYPE, b: TYPE) -> TYPE {
    a + b
}

def functionTakingCall(foo: (Int) -> String) {
    foo(10)
}

# Or in a call
functionTakingCall |a| { a.to_s }
# or
functionTakingCall(|a| { a.to_s })
