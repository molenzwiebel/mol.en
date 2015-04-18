require File.expand_path("../../lib/molen",  __FILE__)
include Molen

describe TypingVisitor do
    def self.type(str, type)
        it "resolves the type of '#{str}' to be #{type}" do
            parser = Molen.create_parser str
            contents = []
            until (n = parser.parse_node).nil?
                contents << n
            end

            mod = Molen::Module.new
            visitor = TypingVisitor.new mod
            body = Body.from(contents)
            body.accept visitor

            expect(body.type.name).to eq type
        end
    end

    def self.fail_on(str)
        it "errors with resolving '#{str}'" do
            expect(lambda {
                parser = Molen.create_parser str
                contents = []
                until (n = parser.parse_node).nil?
                    contents << n
                end

                mod = Molen::Module.new
                visitor = TypingVisitor.new mod
                Body.from(contents).accept visitor
            }).to raise_error
        end
    end

    type "10", "Int"
    type "3.2", "Double"
    type "true", "Bool"
    type "'test'", "String"

    type "var x = 10", "Int"
    type "var x: String", "String"
    type "var x = 12 x = 10", "Int"

    fail_on "var x: String = 12"
    fail_on "var x = 'test' x = 4"
end