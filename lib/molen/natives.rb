
module Molen
    class Module
        def add_natives
            int, double, bool, object, string = self["Int"], self["Double"], self["Bool"], self["Object"], self["String"]

            add_to_s_functions

            int.define_native_function("__add", int, int) { |this, other| builder.ret builder.add this, other }
            int.define_native_function("__sub", int, int) { |this, other| builder.ret builder.sub this, other }
            int.define_native_function("__mul", int, int) { |this, other| builder.ret builder.mul this, other }
            int.define_native_function("__div", int, int) { |this, other| builder.ret builder.sdiv this, other }

            int.define_native_function("__lt", bool, int) { |this, other| builder.ret builder.icmp :ult, this, other }
            int.define_native_function("__lte", bool, int) { |this, other| builder.ret builder.icmp :ule, this, other }
            int.define_native_function("__gt", bool, int) { |this, other| builder.ret builder.icmp :ugt, this, other }
            int.define_native_function("__gte", bool, int) { |this, other| builder.ret builder.icmp :uge, this, other }

            int.define_native_function("__eq", bool, int) { |this, other| builder.ret builder.icmp :eq, this, other }
            int.define_native_function("__neq", bool, int) { |this, other| builder.ret builder.icmp :neq, this, other }

            int.define_native_function("__add", double, double) { |this, other| builder.ret builder.fadd builder.si2fp(this, double.llvm_type), other }
            int.define_native_function("__sub", double, double) { |this, other| builder.ret builder.fsub builder.si2fp(this, double.llvm_type), other }
            int.define_native_function("__mul", double, double) { |this, other| builder.ret builder.fmul builder.si2fp(this, double.llvm_type), other }
            int.define_native_function("__div", double, double) { |this, other| builder.ret builder.fdiv builder.si2fp(this, double.llvm_type), other }

            int.define_native_function("__lt", bool, double) { |this, other| builder.ret builder.fcmp :ult, builder.si2fp(this, double.llvm_type), other }
            int.define_native_function("__lte", bool, double) { |this, other| builder.ret builder.fcmp :ule, builder.si2fp(this, double.llvm_type), other }
            int.define_native_function("__gt", bool, double) { |this, other| builder.ret builder.fcmp :ugt, builder.si2fp(this, double.llvm_type), other }
            int.define_native_function("__lte", bool, double) { |this, other| builder.ret builder.fcmp :uge, builder.si2fp(this, double.llvm_type), other }

            double.define_native_function("__add", double, double) { |this, other| builder.ret builder.fadd this, other }
            double.define_native_function("__sub", double, double) { |this, other| builder.ret builder.fsub this, other }
            double.define_native_function("__mul", double, double) { |this, other| builder.ret builder.fmul this, other }
            double.define_native_function("__div", double, double) { |this, other| builder.ret builder.fdiv this, other }

            double.define_native_function("__lt", bool, double) { |this, other| builder.ret builder.fcmp :ult, this, other }
            double.define_native_function("__lte", bool, double) { |this, other| builder.ret builder.fcmp :ule, this, other }
            double.define_native_function("__gt", bool, double) { |this, other| builder.ret builder.fcmp :ugt, this, other }
            double.define_native_function("__gte", bool, double) { |this, other| builder.ret builder.fcmp :uge, this, other }

            double.define_native_function("__eq", bool, double) { |this, other| builder.ret builder.fcmp :eq, this, other }
            double.define_native_function("__neq", bool, double) { |this, other| builder.ret builder.fcmp :neq, this, other }

            double.define_native_function("__add", double, int) { |this, other| builder.ret builder.fadd this, builder.si2fp(other, double.llvm_type) }
            double.define_native_function("__sub", double, int) { |this, other| builder.ret builder.fsub this, builder.si2fp(other, double.llvm_type) }
            double.define_native_function("__mul", double, int) { |this, other| builder.ret builder.fmul this, builder.si2fp(other, double.llvm_type) }
            double.define_native_function("__div", double, int) { |this, other| builder.ret builder.fdiv this, builder.si2fp(other, double.llvm_type) }

            double.define_native_function("__lt", bool, int) { |this, other| builder.ret builder.fcmp :ult, this, builder.si2fp(other, double.llvm_type) }
            double.define_native_function("__lte", bool, int) { |this, other| builder.ret builder.fcmp :ule, this, builder.si2fp(other, double.llvm_type) }
            double.define_native_function("__gt", bool, int) { |this, other| builder.ret builder.fcmp :ugt, this, builder.si2fp(other, double.llvm_type) }
            double.define_native_function("__gte", bool, int) { |this, other| builder.ret builder.fcmp :uge, this, builder.si2fp(other, double.llvm_type) }

            bool.define_native_function("__or", bool, bool) { |this, other| builder.ret builder.or this, other }
            bool.define_native_function("__and", bool, bool) { |this, other| builder.ret builder.and this, other }
            bool.define_native_function("__eq", bool, bool) { |this, other| builder.ret builder.icmp :eq, this, other }
            bool.define_native_function("__neq", bool, bool) { |this, other| builder.ret builder.icmp, :neq, this, other }
        end

        def add_to_s_functions
            int, double, bool, object, string = self["Int"], self["Double"], self["Bool"], self["Object"], self["String"]

            object.define_native_function("to_s", string) do |this|
                vtable = builder.load builder.struct_gep this, 0
                name_ptr = builder.load builder.struct_gep vtable, 1

                builder.ret perform_sprintf(builder, "#<%s:0x%016lx>", name_ptr, this)
            end

            int.define_native_function("to_s", string) do |this|
                # 12 = (CHAR_BIT * sizeof(int) - 1) / 3 + 2
                builder.ret perform_sprintf(builder, "%i", this)
            end

            bool.define_native_function("to_s", string) do |this|
                builder.ret builder.select this, builder.global_string_pointer("true"), builder.global_string_pointer("false")
            end

            string.define_native_function("to_s", string) do |this|
                builder.ret this
            end

            double.define_native_function("to_s", string) do |this|
                builder.ret perform_sprintf(builder, "%f", this)
            end
        end

    end

    class GeneratingVisitor
        def perform_sprintf(builder, form, *args)
            sprintf_func = llvm_mod.functions["sprintf"] || llvm_mod.functions.add("sprintf", [LLVM::Pointer(LLVM::Int8)], LLVM::Int, varargs: true)
            snprintf_func = llvm_mod.functions["snprintf"] || llvm_mod.functions.add("snprintf", [LLVM::Pointer(LLVM::Int8), LLVM::Int, LLVM::Pointer(LLVM::Int8)], LLVM::Int, varargs: true)

            string_nullptr = builder.int2ptr(LLVM::Int(0), LLVM::Pointer(LLVM::Int8))
            form_ptr = builder.global_string_pointer(form)

            size_needed = builder.call snprintf_func, string_nullptr, LLVM::Int(0), form_ptr, *args

            strbuf = builder.array_malloc(LLVM::Int8, builder.add(size_needed, LLVM::Int(1))) # Add 1 for null term
            builder.call sprintf_func, strbuf, form_ptr, *args
            strbuf
        end
    end
end
