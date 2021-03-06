
module Molen
    class Type
        attr_accessor :name

        def initialize(name)
            @name = name
        end

        def llvm_type
            raise "Unimplemented llvm_type on #{name}"
        end

        def upcastable_to?(other)
            raise "Unimplemented upcastable_to? on #{name}"
        end

        def explicitly_castable_to?(other)
            raise "Unimplemented explicitly_castable_to? on #{name}"
        end

        def metaclass
            @metaclass ||= Metaclass.new(self)
        end

        def pass_as_this?
            true
        end

        def ==(other)
            other.class == self.class && other.name == name
        end

        def hash
            name.hash
        end

        def define_native_function(name, return_type, *args, &block)
            raise "Cannot define native function for type #{self.class.name}" unless self.class.method_defined?(:functions)

            body = NativeBody.new block
            func_def = Function.new name, false, return_type, args.each_with_index.map{|type, id| FunctionArg.new "arg#{id.to_s}", type}, [], body
            func_def.owner_type = self
            func_def.is_prototype_typed = true

            functions[name] = (functions[name] || []) << func_def
        end

        def full_name
            name
        end
    end

    class VoidType < Type
        def initialize
            super "void"
        end

        def upcastable_to?(other)
            return other == self || other.is_a?(ObjectType) || other.is_a?(PointerType) || other.is_a?(FunctionType), 0
        end

        def explicitly_castable_to?(other)
            return other == self
        end

        def pass_as_this?
            false
        end

        def llvm_type
            LLVM.Void
        end
    end

    class ContainedType < Type
        attr_accessor :container

        def initialize(name, cont)
            super name
            @container = cont
        end

        def full_name
            return "#{container.full_name}:#{name}" if container && !container.is_a?(Program)
            name
        end

        def ==(other)
            super && other.container == container
        end
    end

    # A container type is able to contain other types. Sorta
    # like ruby modules or java packages.
    class ModuleType < ContainedType
        attr_accessor :types, :functions, :generic_types, :nodes

        def initialize(name, container, functions = {}, generic_types = {})
            if generic_types && generic_types.values.compact.size > 0 then
                super name + "<" + generic_types.values.map(&:full_name).join(", ") + ">", container
            else
                super name, container
            end

            @types = {}
            @functions = functions
            @generic_types = generic_types
            @nodes = []
        end

        def lookup_type(type_name)
            types[type_name] || generic_types[type_name]
        end

        def upcastable_to?(other)
            return other == self, 0
        end

        def explicitly_castable_to?(other)
            return other == self
        end

        def ==(other)
            super && other.types == types && other.generic_types == generic_types && other.functions == functions
        end

        def hash
            super + [types, functions, generic_types].hash
        end
    end

    class ClassType < ModuleType
        attr_accessor :parent_type

        def initialize(name, parent, container, generic_types = {})
            super name, container, parent ? ParentHash.new(parent.functions) : {}, generic_types

            @parent_type = parent
        end

        def inheritance_chain
            [self] + (parent_type ? parent_type.inheritance_chain : [])
        end

        def ==(other)
            super && other.parent_type == parent_type
        end

        def hash
            super + parent_type.hash
        end
    end

    class PrimitiveType < ClassType
        attr_accessor :llvm_type

        def initialize(name, llvm_type, container)
            super name, nil, container

            @llvm_type = llvm_type
        end

        def llvm_type
            @llvm_type
        end

        def ==(other)
            super && other.llvm_type == llvm_type
        end

        def upcastable_to?(other)
            return (other.is_a?(PrimitiveType) && other.llvm_type == llvm_type), 0
        end

        def explicitly_castable_to?(other)
            upcastable_to?(other).first
        end

        def fp?
            name == "Double" || name == "Float"
        end

        def hash
            super + llvm_type.hash
        end
    end

    class ObjectType < ClassType
        VTABLE_PTR = LLVM::Pointer(LLVM::Pointer(LLVM::Function([], LLVM::Int, varargs: true)))
        TYPEINFO = LLVM::Struct(GeneratingVisitor::VOID_PTR, GeneratingVisitor::VOID_PTR, "_typeinfo")
        TYPEINFO_PTR = LLVM::Pointer(TYPEINFO)
        attr_accessor :vars

        def initialize(name, parent, container, generic_types = {})
            super name, parent, container, generic_types

            @vars = parent ? ParentHash.new(parent.vars) : {}
            @used_functions = []
        end

        def llvm_type
            LLVM::Pointer llvm_struct
        end

        def llvm_struct
            # @llvm_struct ||= begin
            #     llvm_struct = LLVM::Struct("class.#{name}")
            #     llvm_struct.element_types = [VTABLE_PTR, TYPEINFO_PTR] + vars.values.map(&:llvm_type)
            #     llvm_struct
            # end
            LLVM::Struct *([VTABLE_PTR, TYPEINFO_PTR] + vars.values.map(&:llvm_type))
        end

        def ==(other)
            super && other.vars == vars
        end

        def upcastable_to?(other)
            return other == self || (other.is_a?(ObjectType) && inheritance_chain.include?(other)), inheritance_chain.index(other)
        end

        def var_index(name)
            vars.keys.index(name) + 2
        end

        def used_functions
            (parent_type ? parent_type.used_functions : []) + @used_functions
        end

        def use_function(func)
            existing = used_functions.count {|x| (x.owner_type && func.owner_type ? x.owner_type == func.owner_type : true) && x == func} > 0
            @used_functions << func unless existing
        end

        def func_index(node)
            used_functions.index node
        end

        def vtable_functions
            used_functions.map do |func|
                next func if func.overriding_functions.size == 0
                next func unless func.overriding_functions.keys.include? self
                func.overriding_functions.values[func.overriding_functions.keys.index(self)]
            end
        end

        def explicitly_castable_to?(other)
            return false unless other.is_a?(ObjectType)

            is_upcast = upcastable_to?(other).first
            return true if is_upcast

            return other.inheritance_chain.include?(self)
        end

        def hash
            super + vars.hash
        end
    end

    class StructType < ModuleType
        attr_accessor :vars

        def initialize(name, container)
            super name, container

            @vars = {}
        end

        def llvm_type
            LLVM::Pointer llvm_struct
        end

        def llvm_struct
            # @llvm_struct ||= begin
            #     llvm_struct = LLVM::Struct("struct.#{name}")
            #     llvm_struct.element_types = vars.values.map(&:llvm_type)
            #     llvm_struct
            # end
            LLVM::Struct *vars.values.map(&:llvm_type)
        end

        def ==(other)
            super && other.vars == vars
        end

        def upcastable_to?(other)
           return false, 0 unless other.is_a?(StructType)
           return true, 0 if other == self
           return false, 0 if other.instance_variables.size > instance_variables.size

           slice = instance_variables.values.first(other.instance_variables.size)
           return slice == other.instance_variables.values, 0
       end

        def explicitly_castable_to?(other)
            return upcastable_to?(other).first
        end

        def var_index(name)
            vars.keys.index(name)
        end

        def hash
            super + vars.hash
        end
    end

    class FunctionType < Type
        attr_accessor :functions, :captured_vars, :return_type, :args

        def initialize(return_type, args, captured_vars = {})
            super "(#{args.values.map(&:full_name).join(", ")})#{return_type.is_a?(VoidType) ? "" : " -> #{return_type.full_name}"}"

            @return_type = return_type
            @args = args
            @captured_vars = captured_vars
            @functions = {}

            define_native_function("call", return_type, *args.values) do |this, *args|
                scope = builder.load builder.struct_gep(this, 0)
                ptr = builder.load builder.struct_gep(this, 1)

                ret = builder.call ptr, scope, *args
                builder.ret nil if return_type.is_a?(VoidType)
                builder.ret ret unless return_type.is_a?(VoidType)
            end
        end

        def ==(other)
            super && other.return_type == return_type && other.args == args && other.captured_vars == captured_vars
        end

        def llvm_type
            LLVM::Pointer(struct_type)
        end

        def struct_type
            # The first void pointer represents the struct used for holding the captures vars.
            # As these are different even between the same arg/return types we cannot use a
            # more specific type.
            LLVM::Struct(GeneratingVisitor::VOID_PTR, LLVM::Pointer(function_type))
        end

        def var_struct
            LLVM::Struct *captured_vars.map { |k, v| v.is_a?(ObjectType) || v.is_a?(StructType) || v.is_a?(FunctionType) ? v.llvm_type : LLVM::Pointer(v.llvm_type) }
        end

        def function_type
            LLVM::Function([GeneratingVisitor::VOID_PTR] + args.values.map(&:llvm_type), return_type.llvm_type)
        end

        def upcastable_to?(other)
            return other.is_a?(FunctionType) && other.return_type == return_type && other.args.values == args.values, 0
        end

        def explicitly_castable_to?(other)
            return upcastable_to?(other).first
        end
    end

    class PointerType < Type
        attr_accessor :functions, :wrap_type

        def initialize(program, wrap_type)
            super "*" + wrap_type.name

            @wrap_type = wrap_type
            @functions = {}

            define_native_function "get", wrap_type do |this|
                next builder.ret(this) if wrap_type.is_a?(StructType)
                builder.ret builder.load this
            end

            define_native_function "set", VoidType.new, wrap_type do |this, value|
                builder.store value, this
                builder.ret nil
            end

            define_native_function "+", self, program.int do |this, offset|
                builder.ret builder.gep(this, [offset])
            end

            ptr = self
            define_native_function "realloc", self, program.int do |this, new_size|
                realloc_func = mod.functions["realloc"] || mod.functions.add("realloc", [LLVM::Pointer(LLVM::Int8), LLVM::Int], LLVM::Pointer(LLVM::Int8))

                casted_buffer = builder.bit_cast this, LLVM::Pointer(LLVM::Int8)
                new_buffer = builder.call realloc_func, casted_buffer, new_size
                builder.ret builder.bit_cast new_buffer, ptr.llvm_type
            end
        end

        def llvm_type
            wrap_type.is_a?(StructType) ? wrap_type.llvm_type : LLVM::Pointer(wrap_type.llvm_type)
        end

        def ==(other)
            super && other.wrap_type == wrap_type
        end

        def upcastable_to?(other)
            return other == self, 0
        end

        def explicitly_castable_to?(other)
            return true # We can cast pointers to anything. Yolo
        end

        def hash
            super + wrap_type.hash
        end
    end

    class ExternType < ClassType
        attr_accessor :libnames

        def initialize(name, container)
            super name, nil, container

            @libnames = []
        end

        def upcastable_to?(other)
            return other == self, 0
        end

        def explicitly_castable_to?(other)
            other == self
        end

        def metaclass
            self
        end

        def pass_as_this?
            false
        end

        def hash
            super + libnames.hash
        end
    end

    class AliasType < Type
        attr_accessor :type

        def initialize(name, type)
            super name

            @type = type
        end

        def llvm_type
            type.llvm_type
        end

        def upcastable_to?(other)
            if other.is_a?(AliasType) then
                return type.upcastable_to?(other.type)
            end
            type.upcastable_to?(other)
        end

        def explicitly_castable_to?(other)
            if other.is_a?(AliasType) then
                return type.explicitly_castable_to?(other.type)
            end
            type.explicitly_castable_to?(other)
        end

        def pass_as_this?
            type.pass_as_this?
        end

        def ==(other)
            super && type == other.type
        end

        def hash
            super - type.hash
        end
    end

    class Metaclass < Type
        attr_accessor :type, :functions

        def initialize(type)
            super type.name + ":Metaclass"

            @type = type
            @functions = Hash.new { |h,k| h[k] = [] }
        end

        def ==(other)
            other.class == self.class && other.type == type && other.functions == functions
        end

        def upcastable_to?(other)
            return other == self, 0
        end

        def explicitly_castable_to?(other)
            upcastable_to?(other).first
        end

        def pass_as_this?
            false
        end

        def hash
            super + [type, functions].hash
        end
    end
end
