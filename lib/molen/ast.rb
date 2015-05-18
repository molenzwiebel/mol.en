
module Molen
    class Visitor
        def visit_any(node)
            nil
        end
    end

    class ASTNode
        attr_accessor :filename, :line

        def self.attrs(*fields)
            attr_accessor *fields

            define_method "==" do |other|
                return false unless other.class == self.class
                eq = true
                fields.each do |field|
                    eq &&= self.send(field) == other.send(field)
                end
                return eq
            end

            class_eval %Q(
                def initialize(#{fields.map(&:to_s).join ", "})
                    #{fields.map(&:to_s).map{|x| x.include?("body") ? "@#{x} = Body.from #{x}" : "@#{x} = #{x}"}.join("\n")}
                end
            )
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

    class Statement < ASTNode; end;
    class Expression < ASTNode; end;

    class Body < Statement
        include Enumerable
        attrs :contents

        def self.from(other)
            return Body.new [] if other.nil?
            return other if other.is_a? Body
            return Body.new other if other.is_a? ::Array
            Body.new [other]
        end

        def each(&block)
            contents.each &block
        end

        def returns?
            any? do |e|
                next true if e.is_a?(Return)
                next e.returns? if e.class.method_defined?(:returns?)
                false
            end
        end
    end

    class Literal < Expression; attrs :value; end;
    class Str < Literal; end
    class Bool < Literal; end
    class Int < Literal; end
    class Long < Literal; end
    class Double < Literal; end
    class Identifier < Literal; end

    class Import < ASTNode; attrs :value; end
    class Null < ASTNode; attrs; end

    class Constant < Expression
        attrs :names
    end

    class NativeBody < Statement
        attrs :block

        def returns?
            true
        end
    end

    class Call < Expression
        attrs :object, :name, :args, :type_vars
    end

    class MemberAccess < Expression
        attrs :object, :field
    end

    class Assign < Expression
        attrs :target, :value
    end

    class SizeOf < Expression
        attrs :target_type
    end

    class PointerOf < Expression
        attrs :target
    end

    class Cast < Expression
        attrs :target, :type
    end

    class New < Expression
        attrs :type, :args
    end

    class NewArray < Expression
        attrs :elements
    end

    class NewAnonymousFunction < Expression
        attrs :return_type, :args, :body
    end

    class FunctionArg < ASTNode; attrs :name, :type; end;
    class Function < Statement
        attrs :name, :is_static, :return_type, :args, :type_vars, :body
    end

    class If < Statement
        attrs :condition, :if_body, :else_body

        def returns?
            return false unless else_body
            if_body.returns? && else_body.returns?
        end
    end

    class For < Statement
        attrs :init, :cond, :step, :body
    end

    class VarDef < Statement
        attrs :name, :type
    end

    class Return < Statement
        attrs :value
    end

    class ClassDef < Statement
        attrs :name, :superclass, :type_vars, :body
    end

    class ExternalDef < Statement
        attrs :name, :location, :body
    end

    class ExternalFuncDef < Statement
        attrs :name, :return_type, :args
    end

    class StructDef < Statement
        attrs :name, :body
    end

    class ModuleDef < Statement
        attrs :name, :type_vars, :body
    end

    class TypeAliasDef < Statement
        attrs :name, :type
    end

    class Include < Statement
        attrs :type
    end
end
