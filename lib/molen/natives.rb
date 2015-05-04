
module Molen
    class Module
        def add_natives
            int, double, bool, object, string = self["Int"], self["Double"], self["Bool"], self["Object"], self["String"]

            object.define_native_function("to_s", string) do |this|
                sprintf_func = llvm_mod.functions["sprintf"] || llvm_mod.functions.add("sprintf", [string.llvm_type], int.llvm_type, varargs: true)
                strlen_func = llvm_mod.functions["strlen"] || llvm_mod.functions.add("strlen", [string.llvm_type], int.llvm_type)

                vtable = builder.load builder.struct_gep this, 0
                name_ptr = builder.load builder.struct_gep vtable, 1

                name_len = builder.call strlen_func, name_ptr
                buf_len = builder.add name_len, LLVM::Int(23)

                buffer = builder.array_malloc(LLVM::Int8, buf_len)
                builder.call sprintf_func, buffer, builder.global_string_pointer("#<%s:0x%016lx>"), name_ptr, this
                builder.ret buffer
            end

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
    end
end
