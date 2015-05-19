
class ParentHash < Hash
    attr_accessor :parent

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

    def size
        @parent.size + super
    end

    def each(&block)
        @parent.merge(self).each &block
    end

    def clone
        Hash[keys.clone.zip(values.clone)]
    end

    def local_each(&block)
        Hash.instance_method(:each).bind(self).call &block
    end

    def ==(other)
        return false unless other.is_a?(Hash)
        return false if size != other.size
        each do |k, v|
            return false if v != other[k]
        end
        return true
    end
end
