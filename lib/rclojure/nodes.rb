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

  # A deftype* field, seen as a local by its methods: an instance variable
  # of `this`. Only mutable fields can be set!.
  class FieldBinding < LocalBinding
    attr_reader :mutable

    # The instance variable holding field `name`. Prefixed, so fields can't
    # clash with a base class's own (a record's Map internals).
    def self.ivar(name)
      :"@_#{name.gsub(/[^a-zA-Z0-9_]/) { |c| c == '-' ? '_' : "_#{c.ord}_" }}"
    end

    def initialize(name, mutable)
      super(name)
      @mutable = mutable
    end

    def ivar
      FieldBinding.ivar(name)
    end
  end

  # The analyzed forms (an AST), which the Compiler turns into Ruby.
  module Nodes
    Const = Struct.new(:value)
    Local = Struct.new(:binding)
    VarRef = Struct.new(:var)
    # `(var x)` / `#'x`: the Var itself rather than its value.
    TheVar = Struct.new(:var)
    # meta: a node for the var's new metadata, or nil for none.
    Def = Struct.new(:var, :init, :meta, :dynamic)
    # set! on a var (its thread binding).
    VarAssign = Struct.new(:var, :value)
    # set! on a mutable deftype* field.
    LocalAssign = Struct.new(:binding, :value)
    # A value with metadata attached, from a literal collection or fn* form.
    WithMeta = Struct.new(:expr, :meta)
    If = Struct.new(:test, :then_branch, :else_branch)
    Do = Struct.new(:statements, :ret)
    # bindings: [[LocalBinding, node], ...], evaluated sequentially.
    Let = Struct.new(:bindings, :body)
    # Like Let, but every binding is in scope in every init.
    LetFn = Struct.new(:bindings, :body)
    Loop = Struct.new(:bindings, :body)
    # Only ever in tail position of a loop* or fn* method, which it re-runs.
    RecurNode = Struct.new(:args)

    # One arity of a fn*. `rest` is the binding after `&`, or nil. A
    # deftype* method has a `block` binding instead, for the Ruby block.
    FnMethod = Struct.new(:params, :rest, :body, :block) do
      def required
        params.size
      end
    end

    FnNode = Struct.new(:name, :self_binding, :methods)
    # A new class: kind is :type, :record or :reify; fields are
    # FieldBindings; specs evaluate to protocols, Ruby modules or Object;
    # methods are [[name, FnMethod], ...], whose bodies bind `this` to This.
    Deftype = Struct.new(:tag, :kind, :fields, :specs, :methods)
    # The object a deftype* method was called on.
    This = Struct.new
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
