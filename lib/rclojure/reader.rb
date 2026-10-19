require "strscan"

module RClojure
  # Turns source text into rclojure data (forms).
  class Reader
    WHITESPACE = /[\s,]+/
    COMMENT = /;[^\n]*/
    # Characters that end a symbol, number or keyword token.
    TOKEN = /[^\s,()\[\]{}"';`~^@\\]+/
    INTEGER = /\A([-+]?)(\d+)N?\z/
    RATIO = /\A([-+]?\d+)\/(\d+)\z/
    FLOAT = /\A[-+]?\d+(\.\d*)?([eE][-+]?\d+)?M?\z/
    STRING_ESCAPES = { "n" => "\n", "t" => "\t", "r" => "\r", "b" => "\b",
                       "f" => "\f", '"' => '"', "\\" => "\\" }.freeze

    QUOTE            = Symbol.new(nil, "quote")
    SYNTAX_QUOTE     = Symbol.new(nil, "syntax-quote")
    UNQUOTE          = Symbol.new(nil, "unquote")
    UNQUOTE_SPLICING = Symbol.new(nil, "unquote-splicing")
    DEREF            = Symbol.new(nil, "deref")

    # Sentinel returned when a form was discarded with `#_`.
    DISCARDED = Object.new.freeze
    private_constant :DISCARDED

    def self.read_string(source)
      reader = new(source)
      form = reader.read
      reader.skip_whitespace
      reader.error("Unexpected trailing input") unless reader.eof?
      form
    end

    def self.read_all(source)
      reader = new(source)
      forms = []
      loop do
        reader.skip_whitespace
        break if reader.eof?

        forms << reader.read
      end
      forms
    end

    def initialize(source)
      @scanner = StringScanner.new(source)
    end

    def eof?
      @scanner.eos?
    end

    def read
      loop do
        form = read_form
        return form unless form.equal?(DISCARDED)
      end
    end

    def skip_whitespace
      nil while @scanner.skip(WHITESPACE) || @scanner.skip(COMMENT)
    end

    def error(message, klass = ReaderError)
      consumed = @scanner.string.byteslice(0, @scanner.pos)
      line = consumed.count("\n") + 1
      column = consumed.length - (consumed.rindex("\n") || -1)
      raise klass.new(message, line: line, column: column)
    end

    private

    def read_form
      skip_whitespace
      error("Unexpected end of input", EOFError) if eof?

      case @scanner.peek(1)
      when "(" then @scanner.getch; List.new(read_until(")"))
      when "[" then @scanner.getch; Vector.new(read_until("]"))
      when "{" then @scanner.getch; read_map
      when ")", "]", "}" then error("Unmatched delimiter: #{@scanner.peek(1)}")
      when '"' then read_string_literal
      when "'" then @scanner.getch; wrap(QUOTE)
      when "`" then @scanner.getch; wrap(SYNTAX_QUOTE)
      when "~"
        @scanner.getch
        @scanner.skip(/@/) ? wrap(UNQUOTE_SPLICING) : wrap(UNQUOTE)
      when "@" then @scanner.getch; wrap(DEREF)
      when "#" then read_dispatch
      when "\\" then error("Character literals are not supported yet")
      when "^" then error("Metadata is not supported yet")
      else read_atom
      end
    end

    def wrap(symbol)
      List[symbol, read]
    end

    def read_until(closing)
      forms = []
      loop do
        skip_whitespace
        error("Unexpected end of input, expected #{closing}", EOFError) if eof?
        return forms if @scanner.skip(Regexp.new(Regexp.escape(closing)))

        form = read_form
        forms << form unless form.equal?(DISCARDED)
      end
    end

    def read_map
      forms = read_until("}")
      error("Map literal must contain an even number of forms") if forms.size.odd?

      hash = {}
      forms.each_slice(2) do |key, value|
        error("Duplicate key: #{Printer.pr_str(key)}") if hash.key?(key)
        hash[key] = value
      end
      Map.new(hash)
    end

    def read_dispatch
      @scanner.getch # '#'
      case @scanner.getch
      when "{"
        items = read_until("}")
        set = Set.new(items)
        error("Duplicate key in set literal") if set.size != items.size
        set
      when "_"
        read
        DISCARDED
      when nil then error("Unexpected end of input after #", EOFError)
      else error("Unsupported dispatch macro: ##{@scanner.string[@scanner.pos - 1]}")
      end
    end

    def read_string_literal
      @scanner.getch # opening quote
      buffer = +""
      loop do
        char = @scanner.getch
        error("Unterminated string", EOFError) if char.nil?
        return buffer.freeze if char == '"'

        if char == "\\"
          escaped = @scanner.getch
          error("Unterminated string", EOFError) if escaped.nil?
          if escaped == "u"
            hex = @scanner.scan(/\h{4}/) or error("Invalid unicode escape")
            buffer << hex.to_i(16).chr(Encoding::UTF_8)
          else
            buffer << (STRING_ESCAPES[escaped] or error("Unsupported escape character: \\#{escaped}"))
          end
        else
          buffer << char
        end
      end
    end

    def read_atom
      token = @scanner.scan(TOKEN) or error("Unexpected character: #{@scanner.peek(1)}")

      case token
      when "nil" then nil
      when "true" then true
      when "false" then false
      when INTEGER then Integer($2, 10) * ($1 == "-" ? -1 : 1)
      when RATIO then Rational(Integer($1, 10), Integer($2, 10))
      when FLOAT then Float(token.delete_suffix("M"))
      when /\A::/ then error("Auto-resolved keywords are not supported yet")
      when /\A:(.+)\z/ then $1.to_sym
      when /\A[-+]?\d/ then error("Invalid number: #{token}")
      else Symbol.parse(token)
      end
    end
  end
end
