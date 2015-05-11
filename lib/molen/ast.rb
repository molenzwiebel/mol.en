
module Molen
    class Visitor
        def visit_any(node)
            nil
        end
    end

    class ASTNode
        attr_accessor :filename, :line

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

        def self.inherited(klass)
            name = klass.name.split('::').last.gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').tr("-", "_").downcase

            klass.class_eval %Q(
                def accept(visitor)
                    visitor.visit_any(self) || visitor.visit_#{name}(self)
                end
            )

            Visitor.class_eval %Q(
                def visit_#{name}(node)
                    nil
                end
            )
        end

        def raise(msg)
            Kernel::raise "#{filename}##{line}: #{msg}"
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

        def definitely_returns?
            contents.count{ |node| node.is_a?(Return) || node.is_a?(NativeBody) || (node.is_a?(If) and node.definitely_returns?) } > 0
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
    class Long < Literal; end
    class Double < Literal; end
    class Identifier < Literal; end
    class Constant < Literal; end
    class InstanceVariable < Literal; end
    class Import < Literal; end

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

    class PointerMalloc < Expression
        attr_accessor :args
        attr_eq :args

        def initialize(args)
            @args = args
        end
    end

    class PointerOf < Expression
        attr_accessor :expr
        attr_eq :expr

        def initialize(ex)
            @expr = ex
        end
    end

    class Cast < Expression
        attr_accessor :expr, :type
        attr_eq :expr, :type

        def initialize(expr, type)
            @expr, @type = expr, type
        end
    end

    class New < Expression
        attr_accessor :type, :args
        attr_eq :type, :args

        def initialize(type, args)
            @type, @generic_types, @args = type, args
        end
    end

    class NewArray < Expression
        attr_accessor :type, :elements
        attr_eq :type, :elements

        def initialize(type, els)
            @type, @elements = type, els
        end
    end

    class FunctionArg < ASTNode
        attr_accessor :name, :type
        attr_eq :name, :type

        def initialize(name, type)
            @name, @type = name, type
        end
    end

    class Function < Statement
        attr_accessor :owner, :name, :return_type, :args, :body
        attr_eq :name, :return_type, :args, :body

        def initialize(owner, name, ret_type, args, body)
            @owner, @name, @return_type, @args = owner, name, ret_type, args
            @body = Body.from body
        end

        def callable?(types)
            return false, -1 if args.size != types.size
            total_dist = 0
            types.each_with_index do |arg_type, i|
                can, dist = arg_type.castable_to? args[i].type
                return false, -1 unless can
                total_dist += dist
            end
            return true, total_dist
        end

        def eql?(other)
            self == other
        end

        def hash
            [owner, name, return_type, args, body].hash
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
                else_body = If.new else_if.first, else_if.last, else_body, []
            end

            @else = else_body if if_else || elseifs.size > 0
        end

        def definitely_returns?
            unless @else
                return false
            end
            returns = @then.definitely_returns?
            returns = returns && @else.definitely_returns? if @else
            returns
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
        attr_accessor :name, :superclass, :type_vars, :instance_vars, :functions, :class_functions
        attr_eq :name, :superclass, :type_vars, :instance_vars, :functions, :class_functions

        def initialize(name, superclass, vars = [], funcs = [], class_funcs = [], type_vars = [])
            @name, @superclass, @instance_vars, @functions, @class_functions, @type_vars = name, superclass, vars, funcs, class_funcs, type_vars
        end
    end

    class ExternalDef < Statement
        attr_accessor :name, :location, :functions
        attr_eq :name, :location, :functions

        def initialize(name, loc = nil, funcs = [])
            @name, @location, @functions = name, loc, funcs
        end
    end

    class ExternalFunc < Statement
        attr_accessor :owner, :name, :return_type, :args
        attr_eq :name, :return_type, :args

        def initialize(owner, name, return_type, args)
            @owner, @name, @return_type, @args = owner, name, return_type, args
        end

        def callable?(types)
            return false, -1 if args.size != types.size
            total_dist = 0
            types.each_with_index do |arg_type, i|
                can, dist = arg_type.castable_to? args[i].type
                return false, -1 unless can
                total_dist += dist
            end
            return true, total_dist
        end
    end

    class StructDef < Statement
        attr_accessor :name, :vars
        attr_eq :name, :vars

        def initialize(name, vars)
            @name, @vars = name, vars
        end
    end
end
