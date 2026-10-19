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
          warn "Syntax error reading source: #{e.message}"
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
    rescue CompilerError => e
      warn "Syntax error compiling: #{e.message}"
      false
    rescue StandardError, SystemStackError => e
      warn "Execution error (#{e.class.name.split('::').last}): #{e.message}"
      warn "  data: #{Printer.pr_str(e.data)}" if e.is_a?(ExceptionInfo)
      false
    end
  end
end
