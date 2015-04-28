
module Molen
    class ASTNode
        attr_accessor :type
    end

    class Call
        attr_accessor :target_function
    end

    class New
        attr_accessor :target_constructor
    end

    class TypingVisitor < Visitor
        attr_accessor :mod

        def initialize(mod)
            @mod = mod

            @functions = Scope.new
        end

        def visit_int(node)
            node.type = mod["Int"]
        end

        def visit_bool(node)
            node.type = mod["Bool"]
        end

        def visit_double(node)
            node.type = mod["Double"]
        end

        def visit_str(node)
            node.type = mod["String"]
        end
    end
end
