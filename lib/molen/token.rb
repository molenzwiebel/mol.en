
module Molen
    class Token
        attr_accessor :kind, :value, :column, :length, :line_num

        def initialize(kind, value, col, len, line)
            @kind = kind
            @value = value
            @column = col
            @length = len
            @line_num = line
        end

        def is?(val)
            value == val
        end

        def is_kind?(type)
            kind == type
        end

        def method_missing(name, *args)
            return super unless name =~ /is_(.*)?/
            func_kind = /is_(.*)?/.match(name).captures.first
            func_kind.to_sym == kind && (args.size > 0) ? args.first == val : true
        end
    end
end
