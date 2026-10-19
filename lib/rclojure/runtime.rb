module RClojure
  # Owns the namespaces and evaluates forms. Each Runtime is independent.
  class Runtime
    attr_reader :current_ns

    def initialize
      @namespaces = {}
      core = create_namespace("clojure.core")
      Core.install(core)
      @current_ns = create_namespace("user")
      @current_ns.refer(core)
      @analyzer = Analyzer.new(self)
    end

    def find_namespace(name)
      @namespaces[name]
    end

    def eval(form)
      @analyzer.analyze(form).eval(Env.new)
    end

    # Reads and evaluates each form in turn; returns the last value.
    def eval_string(source)
      reader = Reader.new(source)
      result = nil
      loop do
        reader.skip_whitespace
        break if reader.eof?

        result = eval(reader.read)
      end
      result
    end

    def load_file(path)
      eval_string(File.read(path))
    end

    private

    def create_namespace(name)
      @namespaces[name] = Namespace.new(name)
    end
  end
end
