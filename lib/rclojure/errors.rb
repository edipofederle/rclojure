module RClojure
  class Error < StandardError; end

  class ReaderError < Error
    attr_reader :line, :column

    def initialize(message, line:, column:)
      @line = line
      @column = column
      super("#{message} (line #{line}, column #{column})")
    end
  end

  # Raised when input ends in the middle of a form; lets the REPL keep reading.
  class EOFError < ReaderError; end

  # Raised during analysis: malformed special forms, unresolvable symbols,
  # misplaced recur.
  class CompilerError < Error; end

  class ArityError < Error; end

  # Clojure's ex-info: an exception carrying a data map.
  class ExceptionInfo < Error
    attr_reader :data

    def initialize(message, data, cause = nil)
      super(message)
      @data = data
      @cause = cause
    end

    def cause
      @cause || super
    end
  end
end
