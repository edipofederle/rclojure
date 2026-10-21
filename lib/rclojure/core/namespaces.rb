module RClojure
  module Core
    # Namespaces, vars and loading files. The lib machinery built on these
    # (ns, require, use, load) is in core.clj, as in Clojure.
    module Namespaces
      module_function

      def install(ns, runtime)
        define = ->(name, impl) { Core.define(ns, name, impl) }
        the_ns = ->(x) { the_ns(runtime, x) }

        define.("in-ns", lambda { |name|
          raise ArgumentError, "in-ns expects a symbol, got: #{Printer.pr_str(name)}" unless name.is_a?(Symbol)

          runtime.current_ns = runtime.find_or_create_namespace(name.name)
        })
        define.("create-ns", ->(name) { runtime.find_or_create_namespace(name.name) })
        define.("find-ns", ->(name) { runtime.find_namespace(name.name) })
        define.("remove-ns", ->(name) { runtime.remove_namespace(name.name) })
        define.("all-ns", -> { RClojure.seq(runtime.namespaces) })
        define.("the-ns", the_ns)
        define.("ns-name", ->(x) { Symbol.new(nil, the_ns.(x).name) })

        define.("ns-map", ->(x) { symbol_map(the_ns.(x).mappings) })
        define.("ns-interns", ->(x) { symbol_map(the_ns.(x).interns) })
        define.("ns-publics", ->(x) { symbol_map(the_ns.(x).publics) })
        define.("ns-refers", ->(x) { symbol_map(the_ns.(x).refers) })
        define.("ns-aliases", ->(x) { symbol_map(the_ns.(x).aliases) })
        define.("ns-unmap", ->(x, name) { the_ns.(x).unmap(name.name) })
        define.("ns-unalias", ->(x, name) { the_ns.(x).remove_alias(name.name) })
        define.("alias", lambda { |name, target|
          runtime.current_ns.add_alias(name.name, the_ns.(target))
          nil
        })
        define.("refer", ->(ns_name, *filters) { refer(runtime, ns_name, filters) })

        define.("intern", lambda { |x, name, *value|
          var = the_ns.(x).intern(name.name)
          value.empty? ? var : var.bind_root(value.first)
        })
        define.("find-var", lambda { |name|
          raise ArgumentError, "Symbol must be namespace-qualified" unless name.ns

          namespace = runtime.find_namespace(name.ns) or raise ArgumentError, "No such namespace: #{name.ns}"
          namespace.own_var(name.name)
        })
        define.("ns-resolve", lambda { |x, *env_and_name|
          env = env_and_name.size == 2 ? env_and_name.first : nil
          name = env_and_name.last
          RClojure.get(env, name).nil? ? runtime.analyzer.resolve_in(the_ns.(x), name) : nil
        })
        define.("resolve", lambda { |*env_and_name|
          env = env_and_name.size == 2 ? env_and_name.first : nil
          name = env_and_name.last
          RClojure.get(env, name).nil? ? runtime.analyzer.resolve_in(runtime.current_ns, name) : nil
        })
        define.("var?", ->(x) { x.is_a?(Var) })

        define.("load-file", ->(path) { runtime.load_file(path) })
        # Used by load in core.clj, like Clojure's RT.load.
        Core.define(ns, "load-resource", ->(resource) { runtime.load_resource(resource) }).private!
      end

      def the_ns(runtime, x)
        return x if x.is_a?(Namespace)

        runtime.find_namespace(x.name) or raise Error, "No namespace: #{x} found"
      end

      def symbol_map(mappings)
        Map.new(mappings.transform_keys { |name| Symbol.new(nil, name) })
      end

      # Ported from Clojure's refer: maps the public vars of the namespace
      # named ns_name into the current one, filtered by :exclude, :only
      # (or :refer) and :rename.
      def refer(runtime, ns_name, filters)
        namespace = runtime.find_namespace(ns_name.name) or raise Error, "No namespace: #{ns_name}"
        raise ArgumentError, "refer expects filter keyword/value pairs" if filters.size.odd?

        options = filters.each_slice(2).to_h
        publics = namespace.publics
        rename = options[:rename] || Map[]
        excluded = RClojure.items(options[:exclude]).map(&:name)
        selected = options[:refer] == :all ? nil : options[:refer] || options[:only]
        if selected && !selected.is_a?(Sequential)
          raise Error, ":only/:refer value must be a sequential collection of symbols"
        end

        names = selected ? RClojure.items(selected).map(&:name) : publics.keys
        names.each do |name|
          next if excluded.include?(name)

          var = publics[name]
          raise Error, "#{name} #{namespace.own_var(name) ? 'is not public' : 'does not exist'}" unless var

          runtime.current_ns.refer(rename.call(Symbol.new(nil, name))&.name || name, var)
        end
        nil
      end
    end
  end
end
