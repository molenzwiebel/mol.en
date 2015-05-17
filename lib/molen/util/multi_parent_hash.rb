
class MultiParentFunctionLookupHash < Hash
    def initialize(object)
        @object = object
    end

    def [](key)
        value = super
        unless value
           @object.parents.each do |parent|
               value = parent.functions[key] and break
           end
        end
        value
    end

    def values
        object.parents.map(&:functions).map(&:values) + super
    end

    def keys
        object.parents.map(&:functions).map(&:keys) + super
    end

    def each(&block)
        if @object.parents.size > 0 then
            hash = @object.parents.first.functions
            @object.parents.drop(1).each do |parent|
                hash = hash.merge(parent.functions)
            end
            hash.merge(self).each &block
        else
            super
        end
    end

    def local_each(&block)
        Hash.instance_method(:each).bind(self).call &block
    end
end
