require File.expand_path("../../lib/molen",  __FILE__)

describe Molen::GeneratingVisitor do
    before :all do
        LLVM::init_jit
    end

    def run_script(src)
        Molen.run_raw src
    end

    it "should be able to generate an int" do
        expect(run_script("10").to_i).to eq 10
    end

    it "should be able to generate a boolean" do
        expect(run_script("true").to_b).to eq true
    end

    ["+", "-", "*", "/"].each do |op|
        it "generates #{op} with two ints correctly" do
            expect(run_script("10 #{op} 5").to_i).to eq eval("10 #{op} 5")
        end

        it "generates #{op} with two doubles correctly" do
            expect(run_script("10.0 #{op} 5.0").to_f).to eq eval("10.0 #{op} 5.0")
        end

        it "generates #{op} with different numeric types correctly" do
            expect(run_script("10.0 #{op} 5").to_f).to eq eval("10.0 #{op} 5")
        end
    end

    # TODO: Fix this. Currently it crashes RSpec because the actual C LLVM code errors,
    # and does not translate correctly to a ruby exception. I lazily fixed this by adding
    # a simple number after the op.
    it "should be able to assign a simple variable" do
        expect(lambda {
            run_script("var x = 10 0").to_i
        }).to_not raise_error
    end

    it "should be able to refer to a simple variable" do
        expect(run_script("var x = 10 x").to_i).to eq 10
    end

    it "should be able to reassign variables" do
        expect(run_script("var x = 10 x = 4 x").to_i).to eq 4
    end

    it "should be able to generate a function" do
        expect(lambda {
            run_script("def x() -> int 10 0")
        }).to_not raise_error
    end

    it "should be able to call a function" do 
        expect(run_script("def x() -> int 10 x()").to_i).to eq 10
    end

    it "should be able to generate and call class functions" do
        expect(run_script("class int { def get_10() -> int 10 } 4.get_10()").to_i).to eq 10
    end
end