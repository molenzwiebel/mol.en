
class ParentHash < Hash
    def initialize(parent)
        @parent = parent
    end

    def [](key)
        super || @parent[key]
    end

    def values
        @parent.values + super
    end

    def keys
        @parent.keys + super
    end

    def each(&block)
        @parent.merge(self).each &block
    end

    def local_each(&block)
        Hash.instance_method(:each).bind(self).call &block
    end
end
