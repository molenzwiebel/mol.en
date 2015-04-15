
module Molen
    module RuleExtensions
        def maybe(arg = true)
            @maybe = arg
            self
        end
    
        def maybe?
            @maybe || false
        end

        def save(arg = true)
            @save = arg
            self
        end
    
        def save?
            @save || false
        end
    
        def >>(rule)
            Molen::RuleSet.new >> self >> rule
        end
    end

    class Rule
        include Molen::RuleExtensions

        def any_of(*args)
            @pred = [args]
            self
        end

        def expect(arg)
            @pred = arg
            self
        end

        def check(parser)
            err_str = (@pred.is_a?(Array) ? @pred : [@pred || nil]).compact.map{|x| x.is_a?(String) ? "token with value '#{x}'" : "token of kind '#{x.to_s}'"}.join ", "
            tok = parser.current_token

            if @pred.is_a? Array then
                matches = @pred.select{|x| x.is_a?(String) ? tok.is?(x) : tok.is_kind?(x)}.size > 0
                parser.next_token if matches
                return false, "Expected any of: #{err_str}. Received #{tok.kind} with value \"#{tok.value}\"" if not matches and not maybe?
                return true, tok if matches
                return true, nil
            else
                matches = @pred.is_a?(String) ? tok.is?(@pred) : tok.is_kind?(@pred)
                parser.next_token if matches
                return false, "Expected #{err_str}. Received #{tok.kind} with value \"#{tok.value}\"" if not matches and not maybe?
                return true, tok if matches
                return true, nil # Does not match, but it is optional
            end
        end
    end

    class ExpressionParsingRule
        include Molen::RuleExtensions

        def check(parser)
            expr = parser.parse_expression
            return false, "Expected expression." if not expr and not maybe?
            return true, expr if expr
            return true, nil # Does not match but it is optional
        end
    end

    class NodeParsingRule
        include Molen::RuleExtensions

        def check(parser)
            node = parser.parse_node
            return false, "Expected expression or statement." if not node and not maybe?
            return true, node if node
            return true, nil # Does not match but it is optional
        end
    end

    class Run < Struct.new :block, :parser
    end

    class RuleSet
        include Molen::RuleExtensions

        def initialize
            @rules = []
        end

        def rules
            @rules
        end

        def >>(rule)
            raise "Expected rule, ruleset, string or symbol in RuleSet >>. Received #{rule.class.to_s}" unless rule.is_a? String or rule.is_a? Symbol or rule.is_a? Run or rule.respond_to? :check
            if rule.is_a? Run
                res, msg = run(rule.parser, rule.block)
                raise msg if not res
                return msg
            elsif rule.is_a? String or rule.is_a? Symbol then
                r = Rule.new.expect rule
                r.maybe if rule.maybe?
                r.save if rule.save?
                @rules << r
            else
                (@rules << rule)
            end
            self
        end

        def check(parser)
            run parser, nil
        end

        def run(parser, block)
            params = []
            @rules.each do |rule|
                res, msg_or_token = rule.check parser
                return false, msg_or_token if not res and not maybe?
                params << nil if rule.save? and not res
                params << msg_or_token if rule.save? and res
            end
            block.call *params if block
            return true, (params.size == 1 ? params.first : params)
        end
    end
end

class String
    include Molen::RuleExtensions
end

class Symbol
    include Molen::RuleExtensions
end