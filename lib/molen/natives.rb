
module Molen
    class Module
        def add_natives(std = true)
            add_primitive_builtins
            add_object_builtins

            add_std if std
        end

        def add_std
            Dir[File.expand_path("../std/**/*.en",  __FILE__)].each do |file|
                Molen.type(self, Parser.parse(File.read(file), file))
            end
        end

        def add_object_builtins
            self["Object"].define_native_function("to_s", self["String"]) do |this|
                vtable = builder.load builder.struct_gep this, 0
                name_ptr = builder.load builder.struct_gep vtable, 1

                builder.ret perform_sprintf(builder, "#<%s:0x%016lx>", name_ptr, this)
            end
        end

        def add_primitive_builtins
            [self["cuint8"], self["cuint16"], self["cuint32"], self["cuint64"], self["cint8"], self["cint16"], self["cint32"], self["cint64"], self["cfloat"], self["cdouble"]].repeated_permutation 2 do |type1, type2|
                ret_type = greatest_type type1, type2

                ["__add", "__sub", "__mul", "__div"].each do |op|
                    if ret_type.fp? then
                        type1.define_native_function(op, ret_type, type2) do |this, other|
                            converted_this = convert_type(builder, ret_type, type1, this)
                            converted_other = convert_type(builder, ret_type, type2, other)
                            builder.ret generate_numeric_op(builder, op, ret_type, converted_this, converted_other)
                        end
                    else
                        type1.define_native_function(op, type1, type2) do |this, other|
                            converted_this = convert_type(builder, ret_type, type1, this)
                            converted_other = convert_type(builder, ret_type, type2, other)
                            ret = generate_numeric_op(builder, op, ret_type, converted_this, converted_other)
                            builder.ret convert_back(builder, type1, ret_type, ret)
                        end
                    end
                end

                ["__eq", "__lt", "__lte", "__gt", "__gte", "__eq", "__neq"].each do |op|
                    type1.define_native_function(op, self["cint1"], type2) do |this, other|
                        converted_this = convert_type(builder, ret_type, type1, this)
                        converted_other = convert_type(builder, ret_type, type2, other)
                        builder.ret build_comp_op(builder, ret_type, converted_this, converted_other)
                    end
                end

                type1.define_native_function("to_#{type2.name}", type2) do |this|
                    builder.ret convert_type(builder, type2, type1, this)
                end

                int_type = self["Int"]
                type1.define_native_function("to_i", int_type) do |this|
                    val = builder.malloc int_type.llvm_struct
                    builder.store convert_type(builder, int_type, type1, this), builder.struct_gep(val, 1)
                    builder.ret val
                end

                double_type = self["cdouble"]
                type1.define_native_function("to_d", int_type) do |this|
                    val = builder.malloc double_type.llvm_struct
                    builder.store convert_type(builder, int_type, type1, this), builder.struct_gep(val, 1)
                    builder.ret val
                end
            end

            [self["cuint8"], self["cuint16"], self["cuint32"], self["cuint64"], self["cint8"], self["cint16"], self["cint32"], self["cint64"], self["cfloat"], self["cdouble"]].each do |prim_type|
                prim_type.define_native_function("to_s", self["String"]) do |this|
                    builder.ret perform_sprintf(builder, "%#{TYPE_FORMATS[prim_type.name.to_sym]}", this)
                end

                self["String"].define_native_function("__add", self["String"], prim_type) do |this, other|
                    builder.ret perform_sprintf(builder, "%s%#{TYPE_FORMATS[prim_type.name.to_sym]}", this, other)
                end

                int_type = self["cint32"]
                self["Int"].define_native_function("create", nil, prim_type) do |this, arg|
                    builder.store convert_type(builder, int_type, prim_type, arg), builder.struct_gep(this, 1)
                    builder.ret nil
                end

                self["Int"].define_native_function("to_#{prim_type.name}", prim_type) do |this|
                    builder.ret convert_type(builder, prim_type, int_type, builder.load(builder.struct_gep(this, 1)))
                end

                double_type = self["cdouble"]
                self["Double"].define_native_function("create", nil, prim_type) do |this, arg|
                    builder.store convert_type(builder, double_type, prim_type, arg), builder.struct_gep(this, 1)
                    builder.ret nil
                end

                self["Double"].define_native_function("to_#{prim_type.name}", prim_type) do |this|
                    builder.ret convert_type(builder, prim_type, double_type, builder.load(builder.struct_gep(this, 1)))
                end
            end
        end

        def get_rank(type)
            types.keys.index(type.name)
        end

        def greatest_type(type1, type2)
            get_rank(type1) >= get_rank(type2) ? type1 : type2
        end
    end

    class GeneratingVisitor
        def perform_sprintf(builder, form, *args)
            sprintf_func = llvm_mod.functions["sprintf"] || llvm_mod.functions.add("sprintf", [LLVM::Pointer(LLVM::Int8)], LLVM::Int, varargs: true)
            snprintf_func = llvm_mod.functions["snprintf"] || llvm_mod.functions.add("snprintf", [LLVM::Pointer(LLVM::Int8), LLVM::Int, LLVM::Pointer(LLVM::Int8)], LLVM::Int, varargs: true)

            string_nullptr = builder.int2ptr(LLVM::Int(0), LLVM::Pointer(LLVM::Int8))
            form_ptr = builder.global_string_pointer(form)

            size_needed = builder.call snprintf_func, string_nullptr, LLVM::Int(0), form_ptr, *args

            strbuf = builder.array_malloc(LLVM::Int8, builder.add(size_needed, LLVM::Int(1))) # Add 1 for null terminator
            builder.call sprintf_func, strbuf, form_ptr, *args
            strbuf
        end

        def convert_back(builder, ret_type, old_type, obj)
            builder.zext(obj, ret_type.llvm_type) if mod.get_rank(ret_type) > mod.get_rank(old_type)
            builder.trunc(obj, ret_type.llvm_type) if mod.get_rank(ret_type) < mod.get_rank(old_type)
            obj
        end

        def convert_type(b, ret_type, type, obj)
            # Don't cast if we don't have to
            if ret_type == type || (ret_type.integer? && type.integer? && ret_type.llvm_size == type.llvm_size)
                return obj
            end

            if ret_type.fp? then
                if type.fp? then
                    return b.fp_ext(obj, ret_type.llvm_type) if mod.get_rank(ret_type) >mod. get_rank(type)
                    return b.fp_trunc obj, ret_type.llvm_type
                else
                    return b.si2fp obj, ret_type.llvm_type if not type.unsigned?
                    return b.ui2fp obj, ret_type.llvm_type
                end
            else
                if type.fp? then
                    return b.fp2si(obj, ret_type.llvm_type) unless ret_type.unsigned?
                    return b.fp2ui obj, ret_type.llvm_type
                else
                    return b.trunc(obj, ret_type.llvm_type) if mod.get_rank(ret_type) <= mod.get_rank(type)
                    return b.sext(obj, ret_type.llvm_type) unless type.signed?
                    return b.zext obj, ret_type.llvm_type
                end
            end
        end

        def generate_numeric_op(builder, op, ret_type, this, other)
            ops = FP_FUNCS if ret_type.fp?
            ops = UINT_FUNCS if ret_type.unsigned?
            ops = INT_FUNCS unless ops

            builder.send ops[op], this, other
        end

        def generate_comp_op(builder, op, ret_type, this, other)
            ops = ret_type.fp? ? FP_COMP_OPS : ret_type.unsigned? ? UINT_COMP_OPS : INT_COMP_OPS

            builder.send ret_type.fp? ? :fcmp : :icmp, ops[op], this, other
        end

        TYPE_FORMATS = { cuint8: "c", cint8: "c", cint16: "hi", cuint16: "hu", cint32: "i", cuint32: "u", cint64: "li", cuint64: "lu", cfloat: "f", cdouble: "f" }

        INT_FUNCS = { "__add" => :add, "__sub" => :sub, "__mul" => :mul, "__div" => :sdiv }
        UINT_FUNCS = { "__add" => :add, "__sub" => :sub, "__mul" => :mul, "__div" => :udiv }
        FP_FUNCS = { "__add" => :fadd, "__sub" => :fsub, "__mul" => :fmul, "__div" => :fdiv }

        INT_COMP_OPS = { "__eq" => :eq, "__gt"=> :sgt, "__gte" => :sge, "__lt"=> :slt, "__lte" => :sle, "__neq" => :ne }
        UINT_COMP_OPS = { "__eq" => :eq, "__gt"=> :ugt, "__gte" => :uge, "__lt"=> :ult, "__lte" => :ule, "__neq" => :ne }
        FP_COMP_OPS = { "__eq" => :oeq, "__gt"=> :ogt, "__gte" => :oge, "__lt"=> :olt, "__lte" => :ole, "__neq" => :one }
    end
end
