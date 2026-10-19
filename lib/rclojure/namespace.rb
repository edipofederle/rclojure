module RClojure
  # A namespace-level mutable reference, created by `def`.
  class Var
    attr_reader :ns, :name

    def initialize(ns, name)
      @ns = ns
      @name = name.freeze
      @bound = false
    end

    def bind_root(value)
      @root = value
      @bound = true
      self
    end

    def bound?
      @bound
    end

    def deref
      raise Error, "Attempting to use unbound var: #{self}" unless @bound

      @root
    end

    # Vars are callable, delegating to their value: `(#'f 1)`.
    def call(*args)
      RClojure.invoke(deref, args)
    end

    def to_s
      "#'#{ns.name}/#{name}"
    end

    def inspect
      "#<RClojure::Var #{self}>"
    end
  end

  # Maps names to Vars. A namespace sees its own vars first, then the vars
  # of the namespaces it refers (every namespace refers clojure.core).
  class Namespace
    attr_reader :name

    def initialize(name)
      @name = name.freeze
      @vars = {}
      @refers = []
    end

    # Returns this namespace's var for `name`, creating it if needed.
    # Interning a name shadows any referred var of the same name.
    def intern(name)
      @vars[name] ||= Var.new(self, name)
    end

    def refer(namespace)
      @refers << namespace unless @refers.include?(namespace)
    end

    def find_var(name)
      return @vars[name] if @vars.key?(name)

      @refers.each do |ns|
        var = ns.own_var(name)
        return var if var
      end
      nil
    end

    def own_var(name)
      @vars[name]
    end

    def inspect
      "#<RClojure::Namespace #{name}>"
    end
  end
end
