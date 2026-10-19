module RClojure
  # Owns the namespaces and evaluates forms. Each Runtime is independent.
  class Runtime
    CORE_SOURCE = File.expand_path("core.clj", __dir__)

    attr_reader :current_ns, :analyzer

    def initialize
      @namespaces = {}
      @next_id = 0
      @analyzer = Analyzer.new(self)

      core = create_namespace("clojure.core")
      Core.install(core, self)
      @current_ns = core
      load_file(CORE_SOURCE)

      @current_ns = create_namespace("user")
      @current_ns.refer(core)
    end

    def find_namespace(name)
      @namespaces[name]
    end

    # Unique ids for gensyms.
    def next_id
      @next_id += 1
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
