module RClojure
  # A protocol, made by defprotocol: named methods dispatching on the type
  # of their first argument. Implementations are looked up, most specific
  # first, along the class's ancestors (its superclasses and the modules
  # they include, as Clojure searches superclasses and interfaces), and
  # cached per class until the protocol is extended again. nil only uses
  # an implementation for nil, as in Clojure: not Object's.
  #
  # Types implement it directly (deftype, defrecord, reify) with Ruby
  # methods named by method_name, or are extended with fns (extend).
  class Protocol
    # A type's implementation: method keyword => fn taking `this` first.
    Impl = Struct.new(:fns, :inline)

    attr_reader :name

    # name: "ns/Name"; arities: {method keyword => [arg counts]} (including
    # `this`); with extend_via_metadata, a value's metadata can implement
    # methods, keyed by the method fns' qualified symbols.
    def initialize(name, arities, extend_via_metadata)
      @name = name
      @ns = name.split("/", 2).first
      @arities = Map === arities ? arities.to_h.transform_values { |counts| RClojure.items(counts) } : arities
      @extend_via_metadata = RClojure.truthy?(extend_via_metadata)
      @impls = {}.compare_by_identity
      @cache = {}.compare_by_identity
    end

    def method?(method)
      @arities.key?(method)
    end

    def arities(method)
      @arities.fetch(method)
    end

    # The Ruby method a type implementing this protocol directly defines
    # for method: named apart from its other methods, so a protocol method
    # can't replace one of Ruby's (`hash`, say).
    def method_name(method)
      :"#{@name}##{method}"
    end

    # The fn for a protocol method, like the ones defprotocol defines.
    def method_fn(method)
      raise ArgumentError, "No method #{method} in protocol #{@name}" unless method?(method)

      meta_key = Symbol.new(@ns, method.to_s)
      find = ->(x) { find_fn(method, meta_key, x) }
      Builtin.new("#{@ns}/#{method}", ->(x, *args) { RClojure.invoke(find.(x), [x, *args]) },
                  { 1 => ->(x) { RClojure.invoke1(find.(x), x) },
                    2 => ->(x, a) { RClojure.invoke2(find.(x), x, a) },
                    3 => ->(x, a, b) { RClojure.invoke3(find.(x), x, a, b) } })
    end

    # extend: klass (a Class or Module, nil for nil) implements methods
    # with the fns in method_map (method keyword => fn), replacing any
    # earlier extension of klass.
    def self.extend_type(protocol, klass, method_map)
      raise ArgumentError, "#{Printer.pr_str(protocol)} is not a protocol" unless protocol.is_a?(Protocol)

      protocol.add_extension(klass, method_map)
    end

    def add_extension(klass, method_map)
      klass = type_key(klass)
      if @impls[klass]&.inline
        raise ArgumentError, "#{klass.name} already directly implements protocol #{@name}"
      end

      fns = {}
      (method_map || Map[]).each do |method, fn|
        raise ArgumentError, "Can't extend unknown method #{method} of protocol #{@name}" unless method?(method)

        fns[method] = fn
      end
      add_impl(klass, Impl.new(fns, false))
    end

    # deftype & co: klass has a Ruby method (method_name) for each of methods.
    def add_inline(klass, methods)
      fns = methods.to_h do |method|
        ruby_name = method_name(method)
        [method, Builtin.new("#{klass.name}/#{method}", ->(x, *args) { x.__send__(ruby_name, *args) },
                             { 1 => ->(x) { x.__send__(ruby_name) },
                               2 => ->(x, a) { x.__send__(ruby_name, a) },
                               3 => ->(x, a, b) { x.__send__(ruby_name, a, b) } })]
      end
      add_impl(klass, Impl.new(fns, true))
    end

    def satisfies?(x)
      !impl(x).nil?
    end

    # Whether klass (nil for nil) implements or was extended to this protocol.
    def extends?(klass)
      @impls.key?(type_key(klass))
    end

    # The types extended to this protocol (not those implementing it directly).
    def extenders
      RClojure.seq(@impls.reject { |_, impl| impl.inline }.keys.map { |klass| klass.equal?(NilClass) ? nil : klass })
    end

    def to_s
      "#<protocol #{@name}>"
    end
    alias inspect to_s

    private

    def type_key(klass)
      return NilClass if klass.nil?
      raise ArgumentError, "Can't extend a protocol to #{Printer.pr_str(klass)}: not a class or module" unless klass.is_a?(Module)

      klass
    end

    def add_impl(klass, impl)
      @impls[klass] = impl
      @cache = {}.compare_by_identity
      nil
    end

    def impl(x)
      klass = x.class
      @cache.fetch(klass) { @cache[klass] = find_impl(klass) }
    end

    def find_impl(klass)
      return @impls[NilClass] if klass.equal?(NilClass)

      klass.ancestors.each do |ancestor|
        impl = @impls[ancestor]
        return impl if impl
      end
      nil
    end

    # As in Clojure: a direct implementation, then the value's metadata
    # (with extend_via_metadata), then an extension.
    def find_fn(method, meta_key, x)
      impl = impl(x)
      fn = impl.fns[method] if impl&.inline
      if fn.nil? && @extend_via_metadata && x.is_a?(IObj) && (meta = x.meta)
        fn = meta.call(meta_key)
      end
      fn ||= impl.fns[method] if impl && !impl.inline
      return fn if fn

      raise ArgumentError, "No implementation of method: #{method.inspect} of protocol: #'#{@name} " \
                           "found for class: #{x.nil? ? 'nil' : x.class.name}"
    end
  end
end
