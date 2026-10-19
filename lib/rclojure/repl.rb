require "reline"

module RClojure
  # Read-print loop. Evaluation arrives in milestone 2; for now it echoes
  # each form back so the reader can be exercised interactively.
  class REPL
    PROMPT = "user=> ".freeze
    CONTINUATION_PROMPT = "  #_=> ".freeze

    def run
      puts "rclojure #{VERSION} (Ruby #{RUBY_VERSION}) — Ctrl-D to exit"
      buffer = +""
      while (line = Reline.readline(buffer.empty? ? PROMPT : CONTINUATION_PROMPT, true))
        buffer << line << "\n"
        begin
          Reader.read_all(buffer).each { |form| puts Printer.pr_str(form) }
        rescue EOFError
          next # incomplete form: keep reading lines
        rescue Error => e
          warn "Syntax error: #{e.message}"
        end
        buffer = +""
      end
      puts
    end
  end
end
