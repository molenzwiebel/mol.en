
module Molen
    class Scope
        attr_accessor :parent, :this

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

        def values
            (@parent ? @parent.values : []) + @this.values
        end

        def keys
            (@parent ? @parent.keys : []) + @this.keys
        end

        def has_local_key?(k)
            @this.has_key? k
        end

        def ==(other)
            other.class == self.class and other.keys == keys and other.values == values
        end
    end
end
