module RClojure
  # A local binding site (a `let*` name, a fn param, ...). Compared by
  # identity, so a shadowed name gets a distinct binding.
  class LocalBinding
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def inspect
      "#<RClojure::LocalBinding #{name}>"
    end
  end

  # Runtime lexical environment: a chain of frames mapping LocalBindings to values.
  class Env
    def initialize(parent = nil)
      @parent = parent
      @values = {}
    end

    def []=(binding, value)
      @values[binding] = value
    end

    def lookup(binding)
      @values.fetch(binding) { @parent.lookup(binding) }
    end
  end

  # Analyzed forms. Each node evaluates itself against an Env.
  module Nodes
    # Returned (not raised) by a recur in tail position; the enclosing
    # loop* or fn rebinds its locals and runs its body again. The analyzer
    # guarantees it only ever flows through tail positions.
    Recur = Struct.new(:args)

    Const = Struct.new(:value) do
      def eval(_env)
        value
      end
    end

    Local = Struct.new(:binding) do
      def eval(env)
        env.lookup(binding)
      end
    end

    VarRef = Struct.new(:var) do
      def eval(_env)
        var.deref
      end
    end

    # `(var x)` / `#'x`: the Var itself rather than its value.
    TheVar = Struct.new(:var) do
      def eval(_env)
        var
      end
    end

    Def = Struct.new(:var, :init) do
      def eval(env)
        var.bind_root(init.eval(env)) if init
        var
      end
    end

    If = Struct.new(:test, :then_branch, :else_branch) do
      def eval(env)
        value = test.eval(env)
        if value.nil? || value.equal?(false)
          else_branch.eval(env)
        else
          then_branch.eval(env)
        end
      end
    end

    Do = Struct.new(:statements, :ret) do
      def eval(env)
        statements.each { |statement| statement.eval(env) }
        ret.eval(env)
      end
    end

    # bindings: [[LocalBinding, node], ...], evaluated sequentially.
    Let = Struct.new(:bindings, :body) do
      def eval(env)
        frame = Env.new(env)
        bindings.each { |binding, init| frame[binding] = init.eval(frame) }
        body.eval(frame)
      end
    end

    Loop = Struct.new(:bindings, :body) do
      def eval(env)
        frame = Env.new(env)
        bindings.each { |binding, init| frame[binding] = init.eval(frame) }
        loop do
          result = body.eval(frame)
          return result unless result.is_a?(Recur)

          # A fresh frame per iteration, so closures created in an earlier
          # iteration keep the values they captured.
          frame = Env.new(env)
          bindings.each_with_index { |(binding, _), i| frame[binding] = result.args[i] }
        end
      end
    end

    RecurNode = Struct.new(:args) do
      def eval(env)
        Recur.new(args.map { |arg| arg.eval(env) })
      end
    end

    # One arity of a fn*. `rest` is the binding after `&`, or nil.
    FnMethod = Struct.new(:params, :rest, :body) do
      def required
        params.size
      end
    end

    FnNode = Struct.new(:name, :self_binding, :methods) do
      def eval(env)
        closure = Env.new(env)
        fn = Fn.new(name, methods, closure)
        closure[self_binding] = fn if self_binding
        fn
      end
    end

    Invoke = Struct.new(:fn, :args) do
      def eval(env)
        RClojure.invoke(fn.eval(env), args.map { |arg| arg.eval(env) })
      end
    end

    VectorNode = Struct.new(:items) do
      def eval(env)
        Vector.new(items.map { |item| item.eval(env) })
      end
    end

    MapNode = Struct.new(:pairs) do
      def eval(env)
        Map.new(pairs.to_h { |key, value| [key.eval(env), value.eval(env)] })
      end
    end

    SetNode = Struct.new(:items) do
      def eval(env)
        Set.new(items.map { |item| item.eval(env) })
      end
    end

    Throw = Struct.new(:exception) do
      def eval(env)
        value = exception.eval(env)
        raise Error, "Cannot throw #{Printer.pr_str(value)}: not an exception" unless value.is_a?(Exception)

        raise value
      end
    end

    # klass is a Ruby exception class, or Object for `:default`.
    Catch = Struct.new(:klass, :binding, :body)

    Try = Struct.new(:body, :catches, :finally) do
      def eval(env)
        body.eval(env)
      rescue Exception => e # matched against the catch clauses, re-raised if none fits
        clause = catches.find { |c| c.klass === e }
        raise unless clause

        frame = Env.new(env)
        frame[clause.binding] = e
        clause.body.eval(frame)
      ensure
        finally&.eval(env)
      end
    end
  end
end
