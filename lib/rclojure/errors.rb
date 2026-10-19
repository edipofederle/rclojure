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
end
