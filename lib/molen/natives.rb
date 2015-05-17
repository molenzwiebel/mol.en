
module Molen
    class Program
        PRINTF_FORMATS = { bool: "c", char: "c", short: "hi", int: "i", long: "li", float: "f", double: "f" }

        def add_natives
            add_numeric_natives
            add_to_s_natives
            add_other_natives
            add_pointer_malloc

            add_std
        end

        def add_numeric_natives
            [bool, char, short, int, long, double, float].repeated_permutation 2 do |type1, type2|
                bigger_type = greatest_type type1, type2

                ["+", "-", "*", "/"].each do |op|
                    type1.define_native_function(op, bigger_type, type2) do |this, other|
                        converted_this = convert_type this, type1, bigger_type
                        converted_other = convert_type other, type2, bigger_type

                        builder.ret generate_numeric_op op, bigger_type, converted_this, converted_other
                    end
                end

                ["<", "<=", ">", ">=", "==", "!="].each do |op|
                    type1.define_native_function(op, bool, type2) do |this, other|
                        converted_this = convert_type this, type1, bigger_type
                        converted_other = convert_type other, type2, bigger_type

                        builder.ret generate_comp_op op, bigger_type, converted_this, converted_other
                    end
                end

                type1.define_native_function("to_#{type2.name.downcase}", type2) do |this|
                    builder.ret convert_type(this, type1, type2)
                end
            end
        end

        def add_to_s_natives
            [bool, char, short, int, long, double, float].each do |type|
                type.define_native_function "to_s", string do |this|
                    builder.ret perform_sprintf("%#{PRINTF_FORMATS[type.name.downcase.to_sym]}", this)
                end
            end

            object.define_native_function "to_s", string do |this|
                vtable = builder.load builder.struct_gep this, 1
                name_ptr = builder.load builder.struct_gep vtable, 1

                builder.ret perform_sprintf("#<%s:0x%016lx>", name_ptr, this)
            end

            string.define_native_function("+", string, string) do |this, other|
                this = builder.load builder.struct_gep(this, 2)
                other = builder.load builder.struct_gep(other, 2)

                builder.ret perform_sprintf("%s%s", this, other)
            end
        end

        def add_other_natives
            object.define_native_function("is_null", bool) do |this|
                builder.ret builder.icmp :eq, builder.ptr2int(this, LLVM::Int), LLVM::Int(0)
            end

            object.define_native_function("to_bool", bool) do |this|
                builder.ret builder.icmp :ne, builder.ptr2int(this, LLVM::Int), LLVM::Int(0)
            end

            bool.define_native_function("||", bool, bool) do |this, other|
                builder.ret builder.or this, other
            end

            bool.define_native_function("&&", bool, bool) do |this, other|
                builder.ret builder.and this, other
            end
        end

        def add_pointer_malloc
            pointer.metaclass.define_native_function("malloc", @types["*Void"], long) do |size|
                malloc_func = llvm_mod.functions["malloc"] || llvm_mod.functions.add("malloc", [LLVM::Int], LLVM::Pointer(LLVM::Int8))
                builder.ret builder.call malloc_func, builder.trunc(size, LLVM::Int)
            end
        end

        def add_std
            Dir[File.expand_path("../std/*.en",  __FILE__)].each do |file|
                import File.basename(file), nil
            end
        end

        def rank(type)
            types.keys.index type.name
        end

        def greatest_type(type1, type2)
            rank(type1) >= rank(type2) ? type1 : type2
        end
    end

    class GeneratingVisitor
        def perform_sprintf(form, *args)
            sprintf_func = llvm_mod.functions["sprintf"] || llvm_mod.functions.add("sprintf", [LLVM::Pointer(LLVM::Int8)], LLVM::Int, varargs: true)
            snprintf_func = llvm_mod.functions["snprintf"] || llvm_mod.functions.add("snprintf", [LLVM::Pointer(LLVM::Int8), LLVM::Int, LLVM::Pointer(LLVM::Int8)], LLVM::Int, varargs: true)

            string_nullptr = builder.int2ptr(LLVM::Int(0), LLVM::Pointer(LLVM::Int8))
            form_ptr = builder.global_string_pointer(form)

            size_needed = builder.call snprintf_func, string_nullptr, LLVM::Int(0), form_ptr, *args

            strbuf = builder.array_malloc(LLVM::Int8, builder.add(size_needed, LLVM::Int(1))) # Add 1 for null term
            builder.call sprintf_func, strbuf, form_ptr, *args
            allocate_string strbuf
        end

        def convert_type(value, from_type, to_type)
            # Don't cast if we don't have to
            return value if to_type == from_type

            if to_type.fp? then
                if from_type.fp? then
                    return builder.fp_ext(value, to_type.llvm_type) if program.rank(to_type) > program.rank(from_type)
                    return builder.fp_trunc value, to_type.llvm_type
                end
                return builder.si2fp value, to_type.llvm_type
            else
                return builder.fp2si(value, to_type.llvm_type) if from_type.fp?
                return builder.trunc(value, to_type.llvm_type) if program.rank(to_type) <= program.rank(from_type)
                return builder.sext value, to_type.llvm_type
            end
        end

        def generate_numeric_op(op, ret_type, this, other)
            ops = FP_FUNCS if ret_type.fp?
            ops = INT_FUNCS unless ops

            builder.send ops[op], this, other
        end

        def generate_comp_op(op, ret_type, this, other)
            ops = ret_type.fp? ? FP_COMP_OPS : INT_COMP_OPS

            builder.send ret_type.fp? ? :fcmp : :icmp, ops[op], this, other
        end

        INT_FUNCS = { "+" => :add, "-" => :sub, "*" => :mul, "/" => :sdiv }
        FP_FUNCS = { "+" => :fadd, "-" => :fsub, "*" => :fmul, "/" => :fdiv }

        INT_COMP_OPS = { "==" => :eq, ">"=> :sgt, ">=" => :sge, "<"=> :slt, "<=" => :sle, "!=" => :ne }
        FP_COMP_OPS = { "==" => :oeq, ">"=> :ogt, ">=" => :oge, "<"=> :olt, "<=" => :ole, "!=" => :one }
    end
end
