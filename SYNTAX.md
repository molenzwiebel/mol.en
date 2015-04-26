# Mol.en Syntax Ideas

This document exists for me as a reference while implementing the language, and thus might change until mol.en is in a release state. Features might be changed, removed and new ones might be implemented.

### Variables and assignment
Variable names follow the standard conventions you expect in most languages, where you need to start with a `_` or a letter, and after you can have any alphanumeric symbol (and underscores). **NOTE**: In mol.en variable names that start with an uppercase letter are not allowed, because those are reserved for classes.

Creating variables is fairly simple:

    myVariable = 10
    myOtherVariable = 20

Note that you don't need to specify the type, even though mol.en is a statically typed language. Mol.en will figure out what the type is itself. If you want the variable to be a type different from what you assign it (for example a superclass or assigning null), you can use casting operator to do so:

    myVariable = new MyObject() as Object # Here myVariable is of type object
    myVariable = null # This is not allowed! Mol.en cannot figure out the type of myVariable
    myVariable = null as Object # This is allowed

Variables can be freely assigned after they have been declared, mol.en has no concept of final variables.

### Classes and functions
Functions are pretty simple to create:

    def myFunction(param1: int, param2: Object) -> str {
        "Hello, world!"
    }
    myFunction(10, new String())

Here we defined a function named `myFunction`, taking 2 parameters of type `int` and `Object` and returning a `str`. Note that we never specified a return value: mol.en uses the last statement in any given block as the return value, as long as it matches the return value. Not returning anything from a method that specified a return value is illegal: use `null` instead. Calling functions is the simple bracket syntax everyone is used to.

Method overloading is how you would expect it and looks a bit like Java's. When a method with the same number of arguments but different types is found, on an invocation the most "specialized" function is selected. In practice, this means that in the hierarchy of classes, the one closest to the params you pass is selected. An example:

    def myFunction(param1: Object) {}
    def myFunction(param1: MyObject) {}
    myFunction(new MyObject()) # Calls the second function, as it is more specific.

Classes are not too hard either:

    class MyObject :: Superclass {
        var x: int
        var y: double
        var z: bool

        def create() {
            puts("A new MyObject is born!")
        }
    }

This defines a `MyObject` class, with a superclass and 3 instance variables. Note that here we need use `var` in front of the declaration. Assigning an initial value (such as `var x: int = 10`) is illegal, and can be done in the constructor. Note that the constructor is named `create`, and can be invoked using the syntax `new MyObject(args...)`. Class constructors support overloading as described earlier. **NOTE**: Class names in mol.en *have* to start with a capital!

### Types and casting
mol.en has 4 publicly accessible primitive types: `int`, `double`, `bool` and `str`. Those are interally represented in the LLVM IR as their native types (`i32`, `double`, `i1` and `i8*`). Although these are primitives, it is possible to define functions on them (and they have some built-in functions as well). Simply opening up the class is enough:

    class int {
        def times_10() {
            this * 10
        }
    }

    10.times_10() # -> 100

Just like Java, mol.en also has object types of the previously named primitives, namely `Integer`, `Double`, `Boolean` and `String`. These behave like you would expect them to.

### Control flow
If statements:

    if (myCondition) {
        # true
    } elseif (otherCondition) {
        # otherCondition = true
    } else {
        # both are false
    }

For loop:

    for (initialization, condition, step) {
        # Body
    }

Note that the initialization and step are optional. A while loop can thus be created using:

    for (,condition,) {
        # Body
    }

### Operators
Every operator in mol.en is simply a function call. This way, a custom object can override them easily. The names for the methods are simply the operator:

    class MyObject {
        def +(other: Object) {
            10
        }
    }
    new MyObject() + new Integer(3)
