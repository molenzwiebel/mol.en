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
end
