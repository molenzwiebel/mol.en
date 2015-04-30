
module Molen
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
            var = @variable_pointers[node.value]
            builder.load var[:ptr], node.value
        end

        def visit_body(node)
            node.contents.each {|n| n.accept self}
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
