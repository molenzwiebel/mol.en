
module Molen
    def generate(src, filename = "unknown_file")
        Molen.generate(src, filename)
    end

    def self.generate(src, filename = "unknown_file")
        body = parse(src, filename)
        mod = Molen::Module.new
        body.accept TypingVisitor.new(mod)
        visitor = GeneratingVisitor.new(mod, body.type)
        body.accept visitor
        visitor.llvm_mod
    end

    class GeneratingVisitor < Visitor
        attr_accessor :mod, :llvm_mod, :builder

        def initialize(mod, ret_type)
            @mod = mod

            @llvm_mod = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = llvm_mod.functions.add "molen_main", [], ret_type ? ret_type.llvm_type : LLVM.Void
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            llvm_mod.functions.add("main", [], LLVM::Int32) do |f|
                f.basic_blocks.append.build do |b|
                    b.call llvm_mod.functions["molen_main"]
                    b.ret LLVM::Int(0)
                end
            end

            @variable_pointers = Scope.new
            @function_pointers = {}
        end

        def visit_int(node)
            LLVM::Int32.from_i node.value
        end

        def visit_double(node)
            LLVM::Double node.value
        end

        def visit_bool(node)
            node.value ? LLVM::TRUE : LLVM::FALSE
        end

        def visit_str(node)
            builder.global_string_pointer node.value
        end

        def visit_identifier(node)
            builder.load @variable_pointers[node.value], node.value
        end

        def visit_body(node)
            node.contents.each {|n| n.accept self}
        end

        def visit_assign(node)
            if node.name.is_a?(Identifier) then
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                unless @variable_pointers[node.name.value]
                    @variable_pointers.define node.name.value, builder.alloca(node.type.llvm_type, node.name.value)
                end
                builder.store val, @variable_pointers[node.name.value]
                return val
            else
                val = node.value.accept(self)
                val = builder.bit_cast(val, node.type.llvm_type) if node.type != node.value.type

                builder.store val, member_to_ptr(node.name)
                return val
            end
        end

        private
        def member_to_ptr(node)
            ptr_to_obj = node.object.accept(self)
            index = node.ptr_to_obj.type.instance_var_index node.field.value

            return builder.gep ptr_to_obj, [LLVM::Int(0), LLVM::Int(index)], node.field.value + "_ptr"
        end
    end

    class Function
        def ir_name
            if owner then
                "#{owner.type.name}__#{name}<#{args.map(&:type).map(&:name).join ","}>"
            else
                "#{name}<#{args.map(&:type).map(&:name).join ","}>"
            end
        end
    end
end
