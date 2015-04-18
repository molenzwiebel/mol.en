require File.expand_path("../../lib/molen",  __FILE__)

describe Molen::GeneratingVisitor do
    before :all do
        LLVM::init_jit
    end

    def run_script(src, type = "Int", dump = false)
        llvm_mod = Molen.run src, type, dump
        engine = LLVM::JITCompiler.new(llvm_mod)
        engine.run_function llvm_mod.functions["main"]
    end

    it "should be able to generate an int" do
        expect(run_script("10").to_i).to eq 10
    end

    it "should be able to generate a boolean" do
        expect(run_script("true", "Bool").to_b).to eq true
    end

    # TODO: Fix this. Currently it crashes RSpec because the actual C LLVM code errors,
    # and does not translate correctly to a ruby exception.
    #
    # it "should be able to assign a simple variable" do
    #     expect(lambda {
    #         run_script("var x = 10").to_i
    #     }).to_not raise_error
    # end

    it "should be able to refer to a simple variable" do
        expect(run_script("var x = 10 x").to_i).to eq 10
    end

    it "should be able to reassign variables" do
        expect(run_script("var x = 10 x = 4 x").to_i).to eq 4
    end
end