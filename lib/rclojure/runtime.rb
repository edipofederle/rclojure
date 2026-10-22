module RClojure
  # Owns the namespaces and evaluates forms. Each Runtime is independent.
  class Runtime
    CORE_SOURCE = File.expand_path("core.clj", __dir__)
    # rclojure's own libs (clojure.string, clojure.set), searched after the
    # load path, like the Clojure jar on the classpath.
    BUILTIN_SOURCES = File.expand_path("clj", __dir__)

    # Directories `require` searches for libs, like Clojure's classpath:
    # RCLOJURE_PATH (separated like PATH), else the current directory.
    def self.default_load_path
      ENV.fetch("RCLOJURE_PATH", Dir.pwd).split(File::PATH_SEPARATOR)
    end

    attr_reader :analyzer, :load_path

    # cache_dir holds the CoreCache; nil turns caching off.
    def initialize(load_path: Runtime.default_load_path, cache_dir: CoreCache.default_dir)
      @namespaces = {}
      @next_id = 0
      @analyzer = Analyzer.new(self)
      @load_path = load_path

      core = find_or_create_namespace("clojure.core")
      @ns_var = core.intern("*ns*").set_dynamic.bind_root(core)
      Core.install(core, self)
      load_core(cache_dir && CoreCache.new(cache_dir))

      user = find_or_create_namespace("user")
      core.publics.each_value { |var| user.refer(var.name, var) }
      self.current_ns = user
    end

    # The value of clojure.core/*ns*, a dynamic var. Loading a file binds
    # it, so an in-ns there changes the binding (undone after the load);
    # otherwise in-ns sets its root, as at the REPL.
    def current_ns
      @ns_var.deref
    end

    def current_ns=(namespace)
      @ns_var.thread_binding ? @ns_var.set(namespace) : @ns_var.bind_root(namespace)
    end

    def find_namespace(name)
      @namespaces[name]
    end

    def find_or_create_namespace(name)
      @namespaces[name] ||= Namespace.new(name)
    end

    def remove_namespace(name)
      raise Error, "Cannot remove clojure namespace" if name == "clojure.core"

      @namespaces.delete(name)
    end

    def namespaces
      @namespaces.values
    end

    # An alias in the current namespace, else a namespace by full name.
    def resolve_namespace(name)
      current_ns.lookup_alias(name) || find_namespace(name)
    end

    # Unique ids for gensyms.
    def next_id
      @next_id += 1
    end

    # Like Clojure's Compiler.eval, a top-level `do` evaluates its forms one
    # by one, so a form can depend on an earlier one's effects (in-ns, defmacro).
    def eval(form)
      form = @analyzer.macroexpand(form)
      if form.is_a?(ISeq) && form.first == Analyzer::DO
        return form.rest.reduce(nil) { |_, subform| eval(subform) }
      end

      unit = Compiler.new.compile(@analyzer.analyze(form))
      @recorded_units&.push(unit)
      Compiler.run(*unit)
    end

    # Reads and evaluates each form in turn; returns the last value. Forms
    # are read one at a time, so `::kw` resolves in the ns set by earlier forms.
    def eval_string(source)
      reader = new_reader(source)
      result = nil
      loop do
        reader.skip_whitespace
        break if reader.eof?

        result = eval(reader.read)
      end
      result
    end

    def new_reader(source)
      Reader.new(source, ns_resolver: method(:auto_resolve_namespace))
    end

    # Evaluates a file with *ns* bound, as Clojure's load does.
    def load_file(path)
      Var.push_thread_bindings(@ns_var => current_ns)
      begin
        eval_string(File.read(path))
      ensure
        Var.pop_thread_bindings
      end
    end

    # Loads resource ("foo/bar_baz") from the first load path directory
    # (or rclojure's built-in sources) that has resource.clj.
    def load_resource(resource)
      dirs = @load_path + [BUILTIN_SOURCES]
      file = dirs.map { |dir| File.join(dir, "#{resource}.clj") }.find { |path| File.file?(path) }
      raise Error, "Could not locate #{resource}.clj on load path: #{dirs.join(File::PATH_SEPARATOR)}" unless file

      load_file(file)
    end

    # Runs core.clj's cached compiled code if there is any, else loads it
    # from source, recording each form's compiled code for the cache.
    def load_core(cache)
      if (cached = cache&.load(self))
        @next_id, code, constants = cached
        code.call(constants)
      else
        @recorded_units = []
        load_file(CORE_SOURCE)
        cache&.store(@next_id, @recorded_units)
        @recorded_units = nil
      end
    end
    private :load_core

    # For the reader: `::kw` uses the current namespace, `::a/kw` an alias.
    def auto_resolve_namespace(alias_name)
      return current_ns.name unless alias_name

      current_ns.lookup_alias(alias_name)&.name
    end
  end
end
