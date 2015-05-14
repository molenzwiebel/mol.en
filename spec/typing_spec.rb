require "spec_helper"

describe TypingVisitor do
    def self.it_types(str, name)
        it "types '#{str}'" do
            body = Molen.type Molen.parse(str, "typing_spec"), Program.new
            expect(body.contents.last.type).to be_nil unless name
            expect(body.contents.last.type.name).to eq name if name
        end
    end

    def self.it_fails_on(str, err)
        it "successfully deduces that '#{str}' is invalid" do
            body = Molen.parse(str, "typing_spec")
            vis = TypingVisitor.new Program.new
            expect {
                body.accept vis
            }.to raise_error err
        end
    end

    it_types "true", "Bool"
    it_types "10", "Int"
    it_types "10L", "Long"
    it_types "2.2", "Double"
    it_types "'test'", "String"

    it_types "class X {} def test() -> X 10 test()", "X"
    it_types "class X { class Y {} def test() -> Y 10 test() }", nil
    it_fails_on "class X { class Y {} } def test() -> Y 10 test()", /Could not resolve function test's return type! \(Y given\)/
    it_types "def test() -> Int 10 test()", "Int"

    it_types "x = 3", "Int"
    it_types "x = 3 x = 4", "Int"
end
