
module Molen
    class ASTNode; attr_accessor :type; end

    def type(tree, program)
        Molen.type tree, program
    end

    def self.type(tree, program)
        vis = TypingVisitor.new program
        tree.accept vis
        tree
    end

    class TypingVisitor < Visitor
        attr_accessor :program

        def initialize(prog)
            @program = prog
            @type_scope = [prog]
        end

        def visit_body(node)
            node.each { |n| n.accept self }
        end

        def visit_bool(node)
            node.type = program.bool
        end

        def visit_int(node)
            node.type = program.int
        end

        def visit_long(node)
            node.type = program.long
        end

        def visit_double(node)
            node.type = program.double
        end

        def visit_str(node)
            node.type = program.string
        end
    end
end
