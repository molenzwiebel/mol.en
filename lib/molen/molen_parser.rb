
module Molen
    # Alias for create_parser that allows you to call
    # it when including the Molen module.
    def create_parser(source, file)
        Molen.create_parser source, file
    end

    # Creates and populates a new parser with all the
    # parsing rules required for parsing a mol.en src.
    def self.create_parser(source, file)
        Parser.new(source, file) do

        end
    end
end
