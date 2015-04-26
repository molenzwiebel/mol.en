
module Molen
    class ASTNode
        attr_accessor :start_line, :end_line, :start_index, :end_index

        def self.attr_eq(*fields)
            define_method "==" do |other|
                return false unless other.class == self.class
                eq = true
                fields.each do |field|
                    eq &&= self.send(field) == other.send(field)
                end
                return eq
            end
        end
    end

    class Expression < ASTNode; end
    class Statement < ASTNode; end

    class Body < Statement
        attr_accessor :contents
        attr_eq :contents

        def self.from(other)
            return Body.new [] if other.nil?
            return other if other.is_a? Body
            return Body.new other if other.is_a? ::Array
            Body.new [other]
        end

        def initialize(contents)
            @contents = contents
        end

        def empty?
            contents.size == 0
        end
    end

    class Literal < Expression
        attr_accessor :value
        attr_eq :value

        def initialize(val)
            @value = val
        end
    end

    class Str < Literal; end
    class Bool < Literal; end
    class Int < Literal; end
    class Double < Literal; end
    class Identifier < Literal; end
    class Constant < Literal; end

    class Null < Expression
        attr_eq
    end

    class Call < Expression
        attr_accessor :object, :name, :args
        attr_eq :object, :name, :args

        def initialize(obj, name, args)
            @object, @name, @args = obj, name, args
        end
    end

    class MemberAccess < Expression
        attr_accessor :object, :field
        attr_eq :object, :field

        def initialize(obj, field)
            @object, @field = obj, field
        end
    end

    class Assign < Expression
        attr_accessor :name, :value
        attr_eq :name, :value

        def initialize(name, val)
            @name, @value = name, val
        end
    end

    class FunctionArg < ASTNode
        attr_accessor :name, :given_type
        attr_eq :name, :given_type

        def initialize(name, type)
            @name, @given_type = name, type
        end
    end

    class Function < Statement
        attr_accessor :class, :name, :return_type, :args, :body
        attr_eq :class, :name, :return_type, :args, :body

        def initialize(clazz, name, ret_type, args, body)
            @class, @name, @return_type, @args = clazz, name, ret_type, args
            @body = Body.from body
        end
    end

    class If < Statement
        attr_accessor :condition, :then, :else
        attr_eq :condition, :then, :else

        def initialize(cond, if_then, if_else, elseifs)
            @condition = cond
            @then = Body.from if_then

            else_body = Body.from if_else
            elseifs.reverse.each do |else_if|
                else_body = If.new else_if.first, else_if.last, else_body
            end

            @else = else_body unless else_body.empty?
        end
    end

    class For < Statement
        attr_accessor :init, :cond, :step, :body
        attr_eq :init, :cond, :step, :body

        def initialize(init, cond, step, body)
            @init, @cond, @step = init, cond, step
            @body = Body.from body
        end
    end

    class InstanceVar < Statement
        attr_accessor :name, :type
        attr_eq :name, :type

        def initialize(name, type)
            @name, @type = name, type
        end
    end

    class Return < Statement
        attr_accessor :value
        attr_eq :value

        def initialize(val)
            @value = val
        end
    end

    class ClassDef < Statement
        attr_accessor :name, :superclass, :instance_vars, :functions
        attr_eq :name, :superclass, :instance_vars, :functions

        def initialize(name, superclass, vars, funcs)
            @name, @superclass, @instance_vars, @functions = name, superclass, vars, funcs
        end
    end
end
