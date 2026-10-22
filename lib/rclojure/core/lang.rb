module RClojure
  module Core
    # Equality, identity, functions, references, evaluation and exceptions.
    module Lang
      module_function

      def install(ns, runtime)
        define = ->(name, impl, fast = {}) { Core.define(ns, name, impl, fast) }

        define.("=", ->(x, *more) { more.all? { |y| RClojure.equiv?(x, y) } }, { 2 => ->(x, y) { RClojure.equiv?(x, y) } })
        define.("not=", ->(x, *more) { !more.all? { |y| RClojure.equiv?(x, y) } })
        define.("identical?", ->(x, y) { x.equal?(y) })
        define.("compare", ->(x, y) { compare(x, y) })
        define.("sort", lambda { |comparator_or_coll, *coll|
          comparator, coll = coll.empty? ? [nil, comparator_or_coll] : [comparator_or_coll, coll.first]
          sorted_seq(sorted(RClojure.items(coll)) { |a, b| comparison(comparator, a, b) })
        })
        define.("sort-by", lambda { |keyfn, comparator_or_coll, *coll|
          comparator, coll = coll.empty? ? [nil, comparator_or_coll] : [comparator_or_coll, coll.first]
          keyed = RClojure.items(coll).map { |item| [RClojure.invoke(keyfn, [item]), item] }
          sorted_seq(sorted(keyed) { |(a, _), (b, _)| comparison(comparator, a, b) }.map(&:last))
        })
        define.("hash", ->(x) { x.hash })
        define.("not", ->(x) { !RClojure.truthy?(x) })

        define.("nil?", ->(x) { x.nil? })
        define.("some?", ->(x) { !x.nil? })
        define.("true?", ->(x) { x.equal?(true) })
        define.("false?", ->(x) { x.equal?(false) })
        define.("boolean", ->(x) { RClojure.truthy?(x) })
        define.("fn?", ->(x) { x.is_a?(Fn) || x.is_a?(Builtin) })
        define.("type", ->(x) { x&.class })

        define.("apply", lambda { |fn, *args|
          raise ArityError, "Wrong number of args (1) passed to: clojure.core/apply" if args.empty?

          RClojure.invoke(fn, [*args[0...-1], *RClojure.items(args.last)])
        })

        define.("atom", ->(value) { Atom.new(value) })
        define.("deref", ->(ref) { deref(ref) })
        define.("reset!", ->(atom, value) { atom.reset(value) })
        define.("swap!", ->(atom, fn, *args) { atom.swap(fn, args) })

        define.("read-string", ->(source) { Reader.read_string(source, ns_resolver: runtime.method(:auto_resolve_namespace)) })
        define.("eval", ->(form) { runtime.eval(form) })

        define.("meta", ->(x) { x.is_a?(IObj) || x.is_a?(Var) || x.is_a?(Namespace) ? x.meta : nil })
        define.("with-meta", lambda { |x, meta|
          raise Error, "Can't attach metadata to: #{Printer.pr_str(x)}" unless x.is_a?(IObj)

          x.with_meta(meta)
        })
        define.("reset-meta!", ->(ref, meta) { reference!(ref).reset_meta(meta) })
        define.("alter-meta!", lambda { |ref, f, *args|
          reference!(ref).reset_meta(RClojure.invoke(f, [ref.meta, *args]))
        })

        define.("push-thread-bindings", ->(bindings) { Var.push_thread_bindings(bindings.to_h) })
        define.("pop-thread-bindings", -> { Var.pop_thread_bindings })
        define.("var-get", ->(var) { var.deref })
        define.("var-set", ->(var, value) { var.set(value) })
        define.("alter-var-root", lambda { |var, f, *args|
          var.bind_root(RClojure.invoke(f, [var.root, *args]))
          var.root
        })
        define.("bound?", ->(*vars) { vars.all?(&:bound?) })
        define.("thread-bound?", ->(*vars) { vars.all? { |var| !var.thread_binding.nil? } })
        define.("macroexpand-1", ->(form) { runtime.analyzer.macroexpand_1(form) })
        define.("macroexpand", ->(form) { runtime.analyzer.macroexpand(form) })
        define.("gensym", ->(prefix = "G__") { Symbol.new(nil, "#{Printer.str(prefix)}#{runtime.next_id}") })

        define.("ex-info", ->(message, data, cause = nil) { ExceptionInfo.new(message, data, cause) })
        define.("ex-data", ->(ex) { ex.respond_to?(:data) ? ex.data : nil })
        define.("ex-message", ->(ex) { ex.is_a?(Exception) ? ex.message : nil })
        define.("ex-cause", ->(ex) { ex.is_a?(Exception) ? ex.cause : nil })
      end

      # Vars and namespaces hold mutable metadata (Clojure's IReference).
      def reference!(ref)
        return ref if ref.is_a?(Var) || ref.is_a?(Namespace)

        raise Error, "Can't alter metadata of: #{Printer.pr_str(ref)}"
      end

      def deref(ref)
        raise ArgumentError, "Can't deref #{Printer.pr_str(ref)}" unless ref.is_a?(Var) || ref.is_a?(Atom)

        ref.deref
      end

      # Like Clojure's compare: nil sorts first; numbers compare across
      # types; keywords and symbols by namespace (none first), then name;
      # false before true; vectors by size, then item by item. Other
      # values need a Ruby <=> that knows the other one.
      def compare(x, y)
        return 0 if x.equal?(y)
        return -1 if x.nil?
        return 1 if y.nil?

        result =
          case x
          when Numeric then x <=> y if y.is_a?(Numeric)
          when ::Symbol then compare_names(Symbol.parse(x.to_s), Symbol.parse(y.to_s)) if y.is_a?(::Symbol)
          when Symbol then compare_names(x, y) if y.is_a?(Symbol)
          when true, false then (x ? 1 : 0) <=> (y ? 1 : 0) if y == true || y == false
          when Vector then compare_vectors(x, y) if y.is_a?(Vector)
          when Sequential, Map, Set then nil
          else x <=> y
          end
        raise ArgumentError, "Cannot compare #{Printer.pr_str(x)} to #{Printer.pr_str(y)}" if result.nil?

        result
      end

      def compare_names(x, y)
        return -1 if x.ns.nil? && y.ns
        return 1 if x.ns && y.ns.nil?

        ns_order = x.ns.to_s <=> y.ns.to_s
        ns_order.zero? ? x.name <=> y.name : ns_order
      end

      def compare_vectors(x, y)
        return x.size <=> y.size unless x.size == y.size

        x.each_with_index do |item, i|
          order = compare(item, y[i])
          return order unless order.zero?
        end
        0
      end

      # A comparator's verdict on a and b, like Clojure's AFunction.compare:
      # a number is used as is; for a boolean (from `<`, say), true means
      # a first, and otherwise the comparator is asked about b and a.
      def comparison(comparator, a, b)
        return compare(a, b) unless comparator

        result = RClojure.invoke(comparator, [a, b])
        case result
        when true then -1
        when false, nil then RClojure.truthy?(RClojure.invoke(comparator, [b, a])) ? 1 : 0
        when Numeric then result <=> 0
        else raise ArgumentError, "Comparator must return a number or a boolean, got: #{Printer.pr_str(result)}"
        end
      end

      # A stable sort (as Clojure's is): items comparing equal keep their order.
      def sorted(items, &comparison)
        indexed = items.each_with_index.sort do |(a, i), (b, j)|
          order = comparison.call(a, b)
          order.zero? ? i <=> j : order
        end
        indexed.map(&:first)
      end

      # sort's result: a seq, or () when there's nothing to sort.
      def sorted_seq(items)
        items.empty? ? List::EMPTY : ArraySeq.new(items, 0)
      end
    end
  end
end
