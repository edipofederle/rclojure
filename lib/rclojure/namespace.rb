module RClojure
  # A namespace-level mutable reference, created by `def`. Like Clojure's
  # Var: its metadata (always with :ns and :name) says whether it's a
  # :macro or :private, and a dynamic var can be rebound per thread with
  # `binding`, which pushes a Frame of bindings onto a per-thread stack.
  class Var
    Frame = Struct.new(:bindings, :prev)
    Box = Struct.new(:value)

    attr_reader :ns, :name, :meta

    def self.frame
      Thread.current.thread_variable_get(:rclojure_bindings)
    end

    # bindings: {Var => value}. Each new frame holds all the bindings in
    # force, so a lookup checks just the top one.
    def self.push_thread_bindings(bindings)
      frame = self.frame
      boxes = frame ? frame.bindings.dup : {}.compare_by_identity
      bindings.each do |var, value|
        raise Error, "Can't dynamically bind non-dynamic var: #{var.ns.name}/#{var.name}" unless var.dynamic?

        var.thread_bound!
        boxes[var] = Box.new(value)
      end
      Thread.current.thread_variable_set(:rclojure_bindings, Frame.new(boxes, frame))
      nil
    end

    def self.pop_thread_bindings
      frame = self.frame or raise Error, "Pop without matching push"
      Thread.current.thread_variable_set(:rclojure_bindings, frame.prev)
      nil
    end

    def initialize(ns, name)
      @ns = ns
      @name = name.freeze
      @bound = false
      @dynamic = false
      @thread_bound = false
      set_meta(nil)
    end

    def bind_root(value)
      @root = value
      @bound = true
      self
    end

    def bound?
      @bound || !thread_binding.nil?
    end

    # The root value, ignoring any thread binding.
    def root
      @root
    end

    # Replaces the metadata, keeping :ns and :name (Clojure's setMeta).
    def set_meta(meta)
      @meta = (meta || Map[]).assoc(:name, Symbol.new(nil, @name)).assoc(:ns, @ns)
      self
    end

    def reset_meta(meta)
      @meta = meta
    end

    def macro?
      RClojure.truthy?(@meta[:macro])
    end

    # Private vars aren't referred, and can't be named from other
    # namespaces (except through `var`).
    def private?
      RClojure.truthy?(@meta[:private])
    end

    def dynamic?
      @dynamic
    end

    # Set by `def` when the name has :dynamic metadata; never unset, as in Clojure.
    def set_dynamic
      @dynamic = true
      self
    end

    def thread_bound!
      @thread_bound = true
    end

    def thread_binding
      @thread_bound ? Var.frame&.bindings&.[](self) : nil
    end

    def deref
      if @thread_bound && (box = thread_binding)
        return box.value
      end
      raise Error, "Attempting to use unbound var: #{self}" unless @bound

      @root
    end

    # set! on a var: changes its thread binding; there must be one.
    def set(value)
      box = thread_binding or raise Error, "Can't change/establish root binding of: #{@name} with set"
      box.value = value
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
    attr_reader :name, :meta

    def initialize(name)
      @name = name.freeze
      @mappings = {}
      @aliases = {}
      @meta = nil
    end

    def reset_meta(meta)
      @meta = meta
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
