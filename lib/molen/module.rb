
module Molen
    class Module
        attr_accessor :types

        def initialize
            @types = {}
        end

        def [](key)
            types[key]
        end

        def []=(key, val)
            types[key] = val
        end
    end
end
