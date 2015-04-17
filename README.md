# mol.en

My experimental programming language. Written in Ruby, compiles to LLVM IR.

# Examples

    def hello_world() {
        puts("Hello, world!")
    }
    
    def add(a: Double, b: Int) -> Double {
        a + b # Implicit returns!
    }
    
    def map(list: Object[], function: Object(Object)) -> Object[] {
        var ret = new Object[list.size]
        for (var i = 0, i < list.size, i = i + 1) {
            ret[i] = function(list[i])
        }
        ret # Again, implicit returns.
    }
    
    class MyAwesomeClass :: Superclass {
        var x = 0.3
        var y = 10
        
        def create() { } # Method overloading :)
        
        def create(the_x: double, the_y: int) {
            x = the_x
            y = the_y
        }
    }
