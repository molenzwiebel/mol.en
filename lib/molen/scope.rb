
module Molen
    class Scope
        attr_accessor :parent

        def initialize(parent = {})
            @parent = parent
            @this = {}
        end

        def [](key)
            @this.has_key?(key) ? @this[key] : parent[key]
        end

        def []=(key, val)
            @this.has_key?(key) ? @this[key] = val : parent[key] = val
        end

        def define(key, val)
            raise "Redefinition of #{key}" if @this.has_key? key
            @this[key] = val
            val
        end
    end
end