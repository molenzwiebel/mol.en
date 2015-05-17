require 'llvm/core'

module Molen
    class Program
        attr_accessor :types, :functions

        def initialize
            @types = {}
            @functions = {}
            @imports = Set.new

            @types["Bool"] = PrimitiveType.new "Bool", LLVM::Int1
            @types["Char"] = PrimitiveType.new "Char", LLVM::Int8
            @types["Short"] = PrimitiveType.new "Short", LLVM::Int16
            @types["Int"] = PrimitiveType.new "Int", LLVM::Int32
            @types["Long"] = PrimitiveType.new "Long", LLVM::Int64
            @types["Float"] = PrimitiveType.new "Float", LLVM::Float
            @types["Double"] = PrimitiveType.new "Double", LLVM::Double

            @types["Object"] = ObjectType.new "Object", nil
            @types["String"] = ObjectType.new "String", object
            string.vars['pointer'] = PointerType.new char

            @types["Pointer"] = ObjectType.new "Pointer", nil
            add_natives
        end

        def method_missing(name, *args)
            type = types[name.to_s.capitalize]
            return type if type
            super
        end

        def lookup_type(name)
            types[name]
        end

        def import(file, relative_to_dir)
            file = "#{file}.en" unless file.end_with? ".en"

            if relative_to_dir then
                relative_file = File.join(File.dirname(relative_to_dir), file)
                file = File.exists?(relative_file) ? relative_file : File.expand_path("../std/#{file}", __FILE__)
                import_file file
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
