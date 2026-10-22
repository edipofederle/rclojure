require "strscan"

module RClojure
  # Turns source text into rclojure data (forms).
  class Reader
    WHITESPACE = /[\s,]+/
    COMMENT = /;[^\n]*/
    # Characters that end a symbol, number or keyword token.
    TOKEN = /[^\s,()\[\]{}"';`~^@\\]+/
    # What follows a character literal's first character, up to whitespace
    # or a terminating macro character (Clojure's readToken).
    CHARACTER_TOKEN_TAIL = /[^\s,()\[\]{}"`;~^@\\]*/
    CHARACTER_NAMES = { "newline" => "\n", "space" => " ", "tab" => "\t", "backspace" => "\b",
                        "formfeed" => "\f", "return" => "\r" }.freeze
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
    VAR              = Symbol.new(nil, "var")
    FN               = Symbol.new(nil, "fn*")
    AMPERSAND        = Symbol.new(nil, "&")
    # An argument literal in #(): %, %& or %n.
    ARG = /\A%(?:(&)|([1-9][0-9]*))?\z/

    # Sentinel returned when a form was discarded with `#_`.
    DISCARDED = Object.new.freeze
    private_constant :DISCARDED

    # Ids for #() parameter names, like Clojure's RT.nextID.
    def self.next_id
      @next_id = (@next_id || 0) + 1
    end

    def self.read_string(source, ns_resolver: nil)
      reader = new(source, ns_resolver: ns_resolver)
      form = reader.read
      reader.skip_whitespace
      reader.error("Unexpected trailing input") unless reader.eof?
      form
    end

    def self.read_all(source, ns_resolver: nil)
      reader = new(source, ns_resolver: ns_resolver)
      forms = []
      loop do
        reader.skip_whitespace
        break if reader.eof?

        forms << reader.read
      end
      forms
    end

    # ns_resolver resolves auto-resolved keywords: called with nil for
    # `::kw` (the current namespace) or an alias name for `::alias/kw`,
    # it returns a namespace name or nil. Without one, `::kw` is an error.
    def initialize(source, ns_resolver: nil)
      @scanner = StringScanner.new(source)
      @ns_resolver = ns_resolver
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
      when "(" then @scanner.getch; List.from(read_until(")"))
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
      when "\\" then read_character
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
      when "'" then List[VAR, read]
      when "(" then read_fn
      when '"' then read_regex
      when nil then error("Unexpected end of input after #", EOFError)
      else error("Unsupported dispatch macro: ##{@scanner.string[@scanner.pos - 1]}")
      end
    end

    # #(...) => (fn* [p1__N# ...] (...)), like Clojure's FnReader: %, %n
    # and %& in the body become the params, in order, with a rest param
    # for %&; params up to the highest %n are generated even if unused.
    def read_fn
      error("Nested #()s are not allowed") if @fn_args
      @fn_args = {}
      body = List.from(read_until(")"))
      params = (1..(@fn_args.keys.select(&:positive?).max || 0)).map { |n| @fn_args[n] || fn_arg(n) }
      params += [AMPERSAND, @fn_args[-1]] if @fn_args.key?(-1)
      List[FN, Vector.new(params), body]
    ensure
      @fn_args = nil
    end

    def fn_arg(n)
      Symbol.new(nil, "#{n == -1 ? 'rest' : "p#{n}"}__#{Reader.next_id}#")
    end

    # #"..." is a Regexp. As in Clojure, backslash escapes are kept as
    # written, for the regex engine (Ruby's) to interpret.
    def read_regex
      source = +""
      loop do
        char = @scanner.getch or error("EOF while reading regex", EOFError)
        break if char == '"'

        source << char
        source << (@scanner.getch or error("EOF while reading regex", EOFError)) if char == "\\"
      end
      Regexp.new(source).freeze
    rescue RegexpError => e
      error("Invalid regex: #{e.message}")
    end

    # Characters are one-character strings, as in ClojureScript.
    def read_character
      @scanner.getch # backslash
      first = @scanner.getch or error("EOF while reading character", EOFError)
      token = first + @scanner.scan(CHARACTER_TOKEN_TAIL)
      return token.freeze if token.length == 1
      return CHARACTER_NAMES[token] if CHARACTER_NAMES.key?(token)

      case token
      when /\Au(\h{4})\z/
        code = Integer($1, 16)
        error("Invalid character constant: \\u#{$1}") if code.between?(0xD800, 0xDFFF)
        code.chr(Encoding::UTF_8).freeze
      when /\Ao([0-7]{1,3})\z/
        code = Integer($1, 8)
        error("Octal escape sequence must be in range [0, 377].") if code > 0o377
        code.chr(Encoding::UTF_8).freeze
      else error("Unsupported character: \\#{token}")
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
      when /\A::/ then read_auto_resolved_keyword(token)
      when /\A:(.+)\z/ then $1.to_sym
      when /\A[-+]?\d/ then error("Invalid number: #{token}")
      when /\A%/ then @fn_args ? read_fn_arg(token) : Symbol.parse(token)
      else Symbol.parse(token)
      end
    end

    def read_fn_arg(token)
      match = ARG.match(token) or error("arg literal must be %, %& or %integer")
      n = match[1] ? -1 : Integer(match[2] || 1)
      @fn_args[n] ||= fn_arg(n)
    end

    # Like Clojure: `::kw` takes the current namespace, `::alias/kw` an alias's.
    def read_auto_resolved_keyword(token)
      error("Auto-resolved keywords need a namespace to resolve in") unless @ns_resolver
      symbol = Symbol.parse(token[2..])
      ns = !symbol.name.empty? && !token.end_with?("/") && @ns_resolver.call(symbol.ns)
      error("Invalid token: #{token}") unless ns

      :"#{ns}/#{symbol.name}"
    end
  end
end
