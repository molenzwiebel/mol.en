
module Molen
    class Module
        def add_primitives
            int, bool, double = self["int"], self["bool"], self["double"]

            int.add_func("__add", int, int) { |b, f| b.ret b.add f.params[0], f.params[1] }
            int.add_func("__sub", int, int) { |b, f| b.ret b.sub f.params[0], f.params[1] }
            int.add_func("__mul", int, int) { |b, f| b.ret b.mul f.params[0], f.params[1] }
            int.add_func("__div", int, int) { |b, f| b.ret b.div f.params[0], f.params[1] }

            int.add_func("__lt", bool, int) { |b, f| b.ret b.icmp :ult, f.params[0], f.params[1] }
            int.add_func("__lte", bool, int) { |b, f| b.ret b.icmp :ule, f.params[0], f.params[1] }
            int.add_func("__gt", bool, int) { |b, f| b.ret b.icmp :ugt, f.params[0], f.params[1] }
            int.add_func("__lte", bool, int) { |b, f| b.ret b.icmp :uge, f.params[0], f.params[1] }

            int.add_func("__eq", bool, int) { |b, f| b.ret b.icmp :eq, f.params[0], f.params[1] }
            int.add_func("__neq", bool, int) { |b, f| b.ret b.icmp :neq, f.params[0], f.params[1] }

            int.add_func("__add", double, double) { |b, f| b.ret b.fadd b.si2fp(f.params[0], double.llvm_type), f.params[1] }
            int.add_func("__sub", double, double) { |b, f| b.ret b.fsub b.si2fp(f.params[0], double.llvm_type), f.params[1] }
            int.add_func("__mul", double, double) { |b, f| b.ret b.fmul b.si2fp(f.params[0], double.llvm_type), f.params[1] }
            int.add_func("__div", double, double) { |b, f| b.ret b.fdiv b.si2fp(f.params[0], double.llvm_type), f.params[1] }

            int.add_func("__lt", bool, double) { |b, f| b.ret b.fcmp :ult, b.si2fp(f.params[0], double.llvm_type), f.params[1] }
            int.add_func("__lte", bool, double) { |b, f| b.ret b.fcmp :ule, b.si2fp(f.params[0], double.llvm_type), f.params[1] }
            int.add_func("__gt", bool, double) { |b, f| b.ret b.fcmp :ugt, b.si2fp(f.params[0], double.llvm_type), f.params[1] }
            int.add_func("__lte", bool, double) { |b, f| b.ret b.fcmp :uge, b.si2fp(f.params[0], double.llvm_type), f.params[1] }

            double.add_func("__add", double, double) { |b, f| b.ret b.fadd f.params[0], f.params[1] }
            double.add_func("__sub", double, double) { |b, f| b.ret b.fsub f.params[0], f.params[1] }
            double.add_func("__mul", double, double) { |b, f| b.ret b.fmul f.params[0], f.params[1] }
            double.add_func("__div", double, double) { |b, f| b.ret b.fdiv f.params[0], f.params[1] }

            double.add_func("__lt", bool, double) { |b, f| b.ret b.fcmp :ult, f.params[0], f.params[1] }
            double.add_func("__lte", bool, double) { |b, f| b.ret b.fcmp :ule, f.params[0], f.params[1] }
            double.add_func("__gt", bool, double) { |b, f| b.ret b.fcmp :ugt, f.params[0], f.params[1] }
            double.add_func("__lte", bool, double) { |b, f| b.ret b.fcmp :uge, f.params[0], f.params[1] }

            double.add_func("__eq", bool, double) { |b, f| b.ret b.fcmp :eq, f.params[0], f.params[1] }
            double.add_func("__neq", bool, double) { |b, f| b.ret b.fcmp :neq, f.params[0], f.params[1] }

            double.add_func("__add", double, int) { |b, f| b.ret b.fadd f.params[0], b.si2fp(f.params[1], double.llvm_type) }
            double.add_func("__sub", double, int) { |b, f| b.ret b.fsub f.params[0], b.si2fp(f.params[1], double.llvm_type) }
            double.add_func("__mul", double, int) { |b, f| b.ret b.fmul f.params[0], b.si2fp(f.params[1], double.llvm_type) }
            double.add_func("__div", double, int) { |b, f| b.ret b.fdiv f.params[0], b.si2fp(f.params[1], double.llvm_type) }

            double.add_func("__lt", bool, int) { |b, f| b.ret b.fcmp :ult, f.params[0], b.si2fp(f.params[1], double.llvm_type) }
            double.add_func("__lte", bool, int) { |b, f| b.ret b.fcmp :ule, f.params[0], b.si2fp(f.params[1], double.llvm_type) }
            double.add_func("__gt", bool, int) { |b, f| b.ret b.fcmp :ugt, f.params[0], b.si2fp(f.params[1], double.llvm_type) }
            double.add_func("__lte", bool, int) { |b, f| b.ret b.fcmp :uge, f.params[0], b.si2fp(f.params[1], double.llvm_type) }

            bool.add_func("__or", bool, bool) { |b, f| b.ret b.or f.params[0], f.params[1] }
            bool.add_func("__and", bool, bool) { |b, f| b.ret b.and f.params[0], f.params[1] }
            bool.add_func("__eq", bool, bool) { |b, f| b.ret b.icmp :eq, f.params[0], f.params[1] }
            bool.add_func("__neq", bool, bool) { |b, f| b.ret b.icmp, :neq, f.params[0], f.params[1] }
        end
    end
end