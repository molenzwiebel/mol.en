
# The AST (Abstract Syntax Tree). Basically the internal representation of 
# any mol.en file. This tree is generated by the parser.
module Molen
    class Visitor
    end

    class ASTNode
        def self.extended(klass)
            name = klass.simple_name.downcase

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
        def accept_children
        end
    end

    class Expression < ASTNode
    end

    class Statement < ASTNode
    end

    class Expressions < Expression
        include Enumerable
        attr_accessor :expressions

        def self.from(obj)
            case obj
            when nil
                new
            when Expressions
                obj
            when Array
                new obj
            else
                new [obj]
            end
        end

        def initialize(expressions = nil)
            @expressions = expressions
        end

        def each(&block)
            expressions.each &block
        end

        def accept_children(visitor)
            expressions.each { |exp| exp.accept visitor }
        end
    end

    class Bool < Expression
        attr_accessor :value

        def initialize(val)
            @value = val
        end
    end

    class Int < Expression
        attr_accessor :value

        def initialize(val)
            @value = val.to_i
        end
    end

    class Double < Expression
        attr_accessor :value

        def initialize(val)
            @value = val.to_f
        end
    end

    class String < Expression
        attr_accessor :value

        def initialize(val)
            @value = val
        end
    end
end