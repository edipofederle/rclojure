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

  # The analyzed forms (an AST), which the Compiler turns into Ruby.
  module Nodes
    Const = Struct.new(:value)
    Local = Struct.new(:binding)
    VarRef = Struct.new(:var)
    # `(var x)` / `#'x`: the Var itself rather than its value.
    TheVar = Struct.new(:var)
    Def = Struct.new(:var, :init)
    If = Struct.new(:test, :then_branch, :else_branch)
    Do = Struct.new(:statements, :ret)
    # bindings: [[LocalBinding, node], ...], evaluated sequentially.
    Let = Struct.new(:bindings, :body)
    Loop = Struct.new(:bindings, :body)
    # Only ever in tail position of a loop* or fn* method, which it re-runs.
    RecurNode = Struct.new(:args)

    # One arity of a fn*. `rest` is the binding after `&`, or nil.
    FnMethod = Struct.new(:params, :rest, :body) do
      def required
        params.size
      end
    end

    FnNode = Struct.new(:name, :self_binding, :methods)
    Invoke = Struct.new(:fn, :args)
    # A Ruby method call: (. target method args*), with an optional block.
    HostCall = Struct.new(:target, :method, :args, :block)
    # A set! on a Ruby attribute: calls the setter, returns the value.
    HostAssign = Struct.new(:target, :setter, :value)
    VectorNode = Struct.new(:items)
    MapNode = Struct.new(:pairs)
    SetNode = Struct.new(:items)
    Throw = Struct.new(:exception)
    # klass is a Ruby exception class, or Object for `:default`.
    Catch = Struct.new(:klass, :binding, :body)
    Try = Struct.new(:body, :catches, :finally)
  end
end
