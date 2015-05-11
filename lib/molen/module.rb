
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}
            @imports = Set.new

            self["Object"] = object = ObjectType.new "Object"

            self["Bool"] = PrimitiveType.new "Bool", LLVM::Int1, 1

            self["Char"] = PrimitiveType.new "Char", LLVM::Int8, 1
            self["Short"] = PrimitiveType.new "Short", LLVM::Int16, 2
            self["Int"] = PrimitiveType.new "Int", LLVM::Int32, 4
            self["Long"] = PrimitiveType.new "Long", LLVM::Int64, 8
            self["Float"] = PrimitiveType.new "Float", LLVM::Float, 4
            self["Double"] = PrimitiveType.new "Double", LLVM::Double, 8

            self["String"] = ObjectType.new "String", object
            self["String"].instance_variables.define "value", PointerType.new(self, self["Char"])

            self["*Void"] = PointerType.new self, self["Char"]
            self["Pointer"] = ObjectType.new "Pointer"

            add_natives
        end

        def [](key)
            types[key]
        end

        def []=(key, val)
            types[key] = val
        end

        def import(file, relative_to_dir)
            file = "#{file}.en" unless file.end_with? ".en"

            if relative_to_dir then
                dir = File.dirname relative_to_dir
                relative_file = File.join(dir, file)
                if File.exists?(relative_file) then
                    import_file relative_file
                else
                    import_file File.expand_path("../std/#{file}", __FILE__)
                end
            else
                import file, File.expand_path("../std/", __FILE__)
            end
        end

        private
        def import_file(file_loc)
            return if @imports.include? file_loc
            raise "Cannot import #{file_loc}: File not found" unless File.exists?(file_loc)

            @imports.add file_loc
            node = Molen.parse File.read(file_loc), file_loc
            node.accept TypingVisitor.new(self) if node
            node
        end
    end
end
