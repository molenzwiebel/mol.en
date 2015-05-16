require "llvm/core"
require 'llvm/execution_engine'
require 'llvm/transforms/scalar'
require 'llvm/transforms/ipo'
require 'llvm/transforms/vectorize'
require 'llvm/transforms/builder'

module Molen

    def run(src, filename = "unknown_file")
        Molen.run(src, filename)
    end

    def self.run(src, filename = "unknown_file")
        mod = generate(src, filename)
        mod.verify

        LLVM.init_jit

        engine = LLVM::JITCompiler.new mod
        optimizer = LLVM::PassManager.new engine
        optimizer << :arg_promote << :gdce << :global_opt << :gvn << :reassociate << :instcombine << :basicaa << :jump_threading << :simplifycfg << :inline << :mem2reg << :loop_unroll << :loop_rotate << :loop_deletion << :tailcallelim
        5.times { optimizer.run mod }
        mod.verify

        engine.run_function mod.functions["main"]
    end

    def generate(src, filename = "unknown_file")
        Molen.generate(src, filename)
    end

    def self.generate(src, filename = "unknown_file")
        program = Molen::Program.new
        body = type parse(src, filename), program

        visitor = GeneratingVisitor.new(program, body.type || VoidType.new)
        body.accept visitor
        visitor.builder.ret nil

        visitor.mod
    end

    class GeneratingVisitor < Visitor
        VOID_PTR = LLVM::Pointer(LLVM::Int8)
        attr_accessor :program, :mod, :builder

        def initialize(program, ret_type)
            @program = program

            @mod     = LLVM::Module.new("mol.en")
            @builder = LLVM::Builder.new

            main_func = mod.functions.add "molen_main", [], ret_type.llvm_type
            main_func.linkage = :internal
            main_block = main_func.basic_blocks.append("entry")
            builder.position_at_end main_block

            mod.functions.add("main", [], LLVM::Int32) do |f|
                f.basic_blocks.append.build do |b|
                    b.call mod.functions["molen_main"]
                    b.ret LLVM::Int(0)
                end
            end

            @type_infos = {}
            @vtables = {}
            @object_allocator_functions = {}

            @variable_pointers = {}
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
            #allocate_string builder.global_string_pointer(node.value)
        end

        def visit_long(node)
            LLVM::Int64.from_i node.value
        end

        def visit_identifier(node)
            builder.load @variable_pointers[node.value], node.value
        end

        def visit_body(node)
            node.each {|n| n.accept self}
        end
    end
end
