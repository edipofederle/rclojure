require "reline"

module RClojure
  class REPL
    CONTINUATION_PROMPT = "  #_=> ".freeze

    def initialize(runtime = Runtime.new)
      @runtime = runtime
    end

    def run
      puts "rclojure #{VERSION} (Ruby #{RUBY_VERSION}) — Ctrl-D to exit"
      buffer = +""
      while (line = Reline.readline(buffer.empty? ? prompt : CONTINUATION_PROMPT, true))
        buffer << line << "\n"
        begin
          forms = Reader.read_all(buffer)
        rescue EOFError
          next # incomplete form: keep reading lines
        rescue ReaderError => e
          warn REPL.describe_error(e)
          forms = []
        end
        buffer = +""
        forms.each { |form| break unless eval_and_print(form) }
      end
      puts
    end

    private

    def prompt
      "#{@runtime.current_ns.name}=> "
    end

    # Returns false when evaluation failed, so later forms on the same line are skipped.
    def eval_and_print(form)
      puts Printer.pr_str(@runtime.eval(form))
      true
    rescue StandardError, SystemStackError => e
      warn REPL.describe_error(e)
      false
    end

    def self.describe_error(error)
      case error
      when ReaderError then "Syntax error reading source: #{error.message}"
      when CompilerError then "Syntax error compiling: #{error.message}"
      else
        message = "Execution error (#{error.class.name.split('::').last}): #{error.message}"
        message += "\n  data: #{Printer.pr_str(error.data)}" if error.is_a?(ExceptionInfo)
        message
      end
    end
  end
end
