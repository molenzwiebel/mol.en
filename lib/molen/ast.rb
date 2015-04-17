
# The AST (Abstract Syntax Tree). Basically the internal representation of 
# any mol.en file. This tree is generated by the parser.
module Molen
    class Visitor
    end

    class ASTNode
        attr_accessor :line_number, :column_number, :parent

        def self.inherited(klass)
            name = klass.name.split('::').last.downcase

            klass.class_eval %Q(
                def accept(visitor)
                    if visitor.visit_#{name} self
                        accept_children visitor
                    end
                    visitor.end_visit_#{name} self
                end
            )

            Visitor.class_eval %Q(
                def visit_#{name}(node)
                    true
                end
                def end_visit_#{name}(node)
                end
            )
        end

        # To be overridden by any subclasses if they have children that need to be traversed through.
        def accept_children(visitor)
        end
    end

    class Expression < ASTNode
    end

    class Statement < ASTNode
    end

    class Body < Expression
        attr_accessor :nodes

        def self.from(obj)
            case obj
            when nil
                Body.new
            when Body
                obj
            when ::Array
                Body.new obj
            else
                Body.new [obj]
            end
        end

        def initialize(nodes = [])
            @nodes = nodes
            @nodes.each { |e| e.parent = self }
        end

        def accept_children(visitor)
            nodes.each { |exp| exp.accept visitor }
        end

        def ==(other)
            other.class == self.class && other.nodes == nodes
        end
    end

    class Bool < Expression
        attr_accessor :value

        def initialize(val)
            @value = val.to_s == "true"
        end

        def ==(other)
            other.class == self.class && other.value == value
        end
    end

    class Int < Expression
        attr_accessor :value

        def initialize(val)
            @value = val.to_i
        end

        def ==(other)
            other.class == self.class && other.value == value
        end
    end

    class Double < Expression
        attr_accessor :value

        def initialize(val)
            @value = val.to_f
        end

        def ==(other)
            other.class == self.class && other.value == value
        end
    end

    class Str < Expression
        attr_accessor :value

        def initialize(val)
            @value = val
        end

        def ==(other)
            other.class == self.class && other.value == value
        end
    end

    class Null < Expression
        def ==(other)
            other.class == self.class
        end
    end

    class Call < Expression
        attr_accessor :name, :args 

        def initialize(func_name, args = [])
            @name = func_name
            @args = args
            @args.each { |arg| arg.parent = self }
        end

        def accept_children(visitor)
            @args.each { |arg| arg.accept visitor }
        end

        def ==(other)
            other.class == self.class && other.args == args && other.name == name
        end
    end

    class Member < Expression
        attr_accessor :parent, :child

        def initialize(parent, child)
        end

        def accept_children(visitor)
            parent.accept visitor
            child.accept visitor
        end

        def ==(other)
            other.class == self.class && other.parent == parent && other.child == child
        end
    end

    class New < Expression
        attr_accessor :name, :args

        def initialize(name, args = [])
            @name = name
            @args = args
            @args.each { |arg| arg.parent = self }
        end

        def visit_children(visitor)
            @args.each { |arg| arg.accept visitor }
        end

        def ==(other)
            other.class == self.class && other.name == name && other.args == args
        end
    end

    class Var < Expression
        attr_accessor :value

        def initialize(val)
            @value = val
        end

        def ==(other)
            other.class == self.class && other.value == value
        end
    end

    class Binary < Expression
        attr_accessor :op, :left, :right

        def initialize(op, left, right)
            @op = op
            @left = left
            @left.parent = self
            @right = right
            @right.parent = self
        end

        def visit_children(visitor)
            @left.accept visitor
            @right.accept visitor
        end

        def ==(other)
            other.class == self.class && other.op == op && other.left == left && other.right == right
        end
    end

    class Arg < Expression
        attr_accessor :name, :type

        def initialize(name, type)
            @name = name
            @type = type
        end

        def ==(other)
            other.class == self.class && other.name == name && other.type == type
        end
    end

    class Function < Statement
        attr_accessor :name, :ret_type, :args, :body

        def initialize(name, ret_type = nil, args = [], body = nil)
            @name = name
            @ret_type = ret_type || UnresolvedVoidType.new
            @args = args
            @args.each {|arg| arg.parent = self}
            @body = Body.from body
            @body.parent = self
        end

        def visit_children(visitor)
            @args.each { |a| a.accept visitor }
            @body.accept visitor
        end

        def ==(other)
            other.class == self.class && other.name == name && other.args == args && other.body == body
        end
    end

    class If < Statement
        attr_accessor :cond, :then, :elseifs, :else

        def initialize(cond, if_then, if_else = nil, elseifs = [])
            @cond = cond
            @cond.parent = self
            @then = Body.from if_then
            @then.parent = self
            @elseifs = elseifs.map {|else_if| [else_if.first, Body.from(else_if.last)]} if elseifs
            @elseifs.each {|else_if| else_if.first.parent = self; else_if.last.parent = self} if elseifs
            @else = Body.from if_else
            @else.parent = self
        end

        def accept_children(visitor)
            @cond.accept visitor
            @then.accept visitor
            @else.accept visitor
        end

        def ==(other)
            other.class == self.class && other.cond == cond && other.then == @then && other.elseifs == elseifs && other.else == @else
        end
    end

    class For < Statement
        attr_accessor :init, :cond, :step, :body

        def initialize(cond, init = nil, step = nil, body = nil)
            @cond = cond
            @cond.parent = self
            @init = init
            @init.parent = self if init
            @step = step
            @step.parent = self if step
            @body = Body.from body
            @body.parent = self
        end

        def visit_children(visitor)
            @init.accept visitor if @init
            @cond.accept visitor
            @step.accept visitor if @step
            @body.accept visitor
        end

        def ==(other)
            other.class == self.class && other.init == init && other.cond == cond && other.step == step && other.body == body
        end
    end

    class VarDef < Statement
        attr_accessor :name, :type, :value

        def initialize(name, type = nil, value = nil)
            @name = name
            @name.parent = self
            @type = type
            @value = value
            @value.parent = self if value
        end

        def accept_children(visitor)
            @value.accept visitor if @value
        end

        def ==(other)
            other.class == self.class && other.name == name && other.value == value
        end
    end

    class Return < Statement
        attr_accessor :value

        def initialize(value = nil)
            @value = value
            @value.parent = self if value
        end

        def accept_children(visitor)
            @value.accept visitor if @value
        end

        def ==(other)
            other.class == self.class && other.value == value
        end
    end

    class ClassDef < Statement
        attr_accessor :name, :superclass, :vars, :funcs

        def initialize(name, superclass = nil, var_defs = [], funcs = [])
            @name = name
            @superclass = superclass
            @vars = var_defs
            @vars.each {|var| var.parent = self}
            @funcs = funcs
            @funcs.each {|func| func.parent = self}
        end

        def visit_children(visitor)
            @var_defs.each {|var| var.accept visitor}
            @funcs.each {|func| func.accept visitor}
        end

        def ==(other)
            other.class == self.class && other.name == name && other.superclass == superclass && other.vars == vars && other.funcs = funcs
        end
    end
end