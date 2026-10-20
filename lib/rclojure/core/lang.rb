module RClojure
  module Core
    # Equality, identity, functions, references, evaluation and exceptions.
    module Lang
      module_function

      def install(ns, runtime)
        define = ->(name, impl) { Core.define(ns, name, impl) }

        define.("=", ->(x, *more) { more.all? { |y| RClojure.equiv?(x, y) } })
        define.("not=", ->(x, *more) { !more.all? { |y| RClojure.equiv?(x, y) } })
        define.("identical?", ->(x, y) { x.equal?(y) })
        define.("compare", ->(x, y) { compare(x, y) })
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

        define.("read-string", ->(source) { Reader.read_string(source) })
        define.("eval", ->(form) { runtime.eval(form) })

        define.("set-macro!", ->(var) { var.macro! })
        define.("macroexpand-1", ->(form) { runtime.analyzer.macroexpand_1(form) })
        define.("macroexpand", ->(form) { runtime.analyzer.macroexpand(form) })
        define.("gensym", ->(prefix = "G__") { Symbol.new(nil, "#{Printer.str(prefix)}#{runtime.next_id}") })

        define.("ex-info", ->(message, data, cause = nil) { ExceptionInfo.new(message, data, cause) })
        define.("ex-data", ->(ex) { ex.respond_to?(:data) ? ex.data : nil })
        define.("ex-message", ->(ex) { ex.is_a?(Exception) ? ex.message : nil })
        define.("ex-cause", ->(ex) { ex.is_a?(Exception) ? ex.cause : nil })
      end

      def deref(ref)
        raise ArgumentError, "Can't deref #{Printer.pr_str(ref)}" unless ref.is_a?(Var) || ref.is_a?(Atom)

        ref.deref
      end

      # nil sorts before everything; otherwise Ruby's <=>.
      def compare(x, y)
        return 0 if x.nil? && y.nil?
        return -1 if x.nil?
        return 1 if y.nil?

        result = x <=> y
        raise ArgumentError, "Cannot compare #{Printer.pr_str(x)} to #{Printer.pr_str(y)}" if result.nil?

        result
      end
    end
  end
end
