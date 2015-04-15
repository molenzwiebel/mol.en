
module Molen
    # This is the main mol.en lexer responsible for taking an input string and
    # splitting it up in little pieces known as tokens. Although the rules at
    # the top are tailored for mol.en, the rest of the parser can be used for
    # any language.
    class Lexer
        RULES = {
            # Regex for matching token  => token kind

            /[+-]?[0-9]*\.[0-9][0-9]*/  => :double,
            /[+-]?[0-9]+/               => :integer,
            /(["'])(\\?.)*?\1/          => :string,

            /true/                      => :true,
            /false/                     => :false,
            /null/                      => :null,

            /def/                       => :keyword,
            /if/                        => :keyword,
            /elseif/                    => :keyword,
            /else/                      => :keyword,
            /for/                       => :keyword,
            /var/                       => :keyword,
            /return/                    => :keyword,
            /new/                       => :keyword,
            /var/                       => :keyword,
            /class/                     => :keyword,

            /[_a-zA-Z][_0-9a-zA-Z]*/    => :identifier, # We need this after the keywords or it will match them as identifiers.

            /\{/                        => :begin_block,
            /\}/                        => :end_block,
            /\(/                        => :lparen,
            /\)/                        => :rparen,

            /::/                        => :special,
            /:/                         => :special,
            /=>/                        => :special,
            /->/                        => :special,
            /,/                         => :special,
            /\[/                        => :special,
            /\]/                        => :special,

            /\+/                        => :operator,
            /\//                        => :operator,
            /\-/                        => :operator,
            /\*/                        => :operator,
            /\./                        => :operator,

            /&&/                        => :operator,
            /\|\|/                      => :operator,
            />=?/                       => :operator,
            /<=?/                       => :operator,

            # Note that the order of these matters! This lexer is lazy, so it will always match `=` over `==` unless we specify `==` first.
            /==/                        => :operator,
            /=/                         => :operator,
            /!=/                        => :operator
        }

        def initialize(source)
            @scanner = StringScanner.new source
            @curpos  = 0
        end

        def next_token
            if @scanner.eos? then
                return Token.new nil, :eof, @scanner.charpos, @scanner.charpos
            end

            return next_token if @scanner.scan /\s+/

            RULES.each do |matcher, kind|
                if content = @scanner.scan(matcher) then
                    pos = @scanner.charpos
                    tok = Token.new content, kind, @curpos, pos + 1
                    @curpos = pos

                    return tok
                end
            end

            raise "Unexpected character '#{@scanner.getch}' at position #{@scanner.charpos} while scanning."
        end
    end
end