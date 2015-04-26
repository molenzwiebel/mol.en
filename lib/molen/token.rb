
module Molen
    class Token
        attr_accessor :kind, :value, :start_pos, :end_pos, :line_num

        def initialize(kind, value, startp, endp, line)
            @kind = kind
            @value = value
            @start_pos = startp
            @end_pos = endp
            @line_num = line
        end

        def is?(val)
            value == val
        end

        def method_missing(name, *args)
            return super unless name =~ /is_(.*)?/
            func_kind = /is_(.*)?/.match(name).captures.first
            func_kind.to_sym == kind && (args.size > 0) ? args.first == val : true
        end
    end
end
