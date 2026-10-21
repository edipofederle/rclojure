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

    def macro?
      @macro
    end

    def macro!
      @macro = true
      self
    end

    # Set by defn-; private vars aren't referred, and can't be named from
    # other namespaces (except through `var`).
    def private?
      @private
    end

    def private!
      @private = true
      self
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

    # Vars are marshaled by name (for the core cache) and loaded by
    # interning that name in the Runtime being loaded into.
    def _dump(_level)
      "#{ns.name}/#{name}"
    end

    def self._load(qualified_name)
      runtime = CoreCache.loading_runtime or raise TypeError, "Vars can only be loaded by a Runtime"
      ns_name, name = qualified_name.split("/", 2)
      runtime.find_or_create_namespace(ns_name).intern(name)
    end
  end

  # Like Clojure's Namespace: mappings from names to Vars (its own, plus
  # those referred from other namespaces) and aliases to other namespaces.
  class Namespace
    attr_reader :name

    def initialize(name)
      @name = name.freeze
      @mappings = {}
      @aliases = {}
    end

    # Returns this namespace's var for `name`, creating it if needed. As in
    # Clojure, a referred var of the same name is replaced, with a warning.
    def intern(name)
      existing = @mappings[name]
      return existing if existing&.ns.equal?(self)

      var = Var.new(self, name)
      warn "WARNING: #{name} already refers to: #{existing} in namespace: #{@name}, being replaced by: #{var}" if existing
      @mappings[name] = var
    end

    # Maps name to another namespace's var. Never replaces a var interned
    # here (Clojure only warns about that when var isn't from clojure.core).
    def refer(name, var)
      existing = @mappings[name]
      return var if existing.equal?(var)

      if existing&.ns.equal?(self)
        unless var.ns.name == "clojure.core"
          warn "REJECTED: attempt to replace interned var #{existing} with #{var} in #{@name}, you must ns-unmap first"
        end
        return existing
      end

      warn "WARNING: #{name} already refers to: #{existing} in namespace: #{@name}, being replaced by: #{var}" if existing
      @mappings[name] = var
    end

    def unmap(name)
      @mappings.delete(name)
      nil
    end

    def find_var(name)
      @mappings[name]
    end

    # The var interned here under name, ignoring referred ones.
    def own_var(name)
      var = @mappings[name]
      var if var&.ns.equal?(self)
    end

    def mappings
      @mappings.dup
    end

    def interns
      @mappings.select { |_, var| var.ns.equal?(self) }
    end

    def publics
      interns.reject { |_, var| var.private? }
    end

    def refers
      @mappings.reject { |_, var| var.ns.equal?(self) }
    end

    def add_alias(name, namespace)
      existing = @aliases[name]
      if existing && !existing.equal?(namespace)
        raise Error, "Alias #{name} already exists in namespace #{@name}, aliasing #{existing.name}"
      end

      @aliases[name] = namespace
    end

    def remove_alias(name)
      @aliases.delete(name)
      nil
    end

    def lookup_alias(name)
      @aliases[name]
    end

    def aliases
      @aliases.dup
    end

    def to_s
      "#namespace[#{@name}]"
    end

    def inspect
      "#<RClojure::Namespace #{@name}>"
    end
  end
end
