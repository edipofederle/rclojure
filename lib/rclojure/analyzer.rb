module RClojure
  # Turns forms into Nodes, resolving symbols and validating special forms.
  class Analyzer
    SPECIAL_FORMS = %w[def if do let* loop* recur fn* quote var throw try . new set!].freeze
    DOT = Symbol.new(nil, ".")
    NEW = Symbol.new(nil, "new")
    DO = Symbol.new(nil, "do")
    SYNTAX_QUOTE = Symbol.new(nil, "syntax-quote")
    AMPERSAND = Symbol.new(nil, "&")
    CATCH = Symbol.new(nil, "catch")
    FINALLY = Symbol.new(nil, "finally")
    NIL_NODE = Nodes::Const.new(nil)

    # Compile-time context: visible locals (name => LocalBinding) and the
    # arity of the innermost recur target (nil when there is none,
    # :try when a try block sits between the recur and its target).
    Scope = Struct.new(:locals, :recur_arity) do
      def with_locals(bindings)
        Scope.new(locals.merge(bindings.to_h { |b| [b.name, b] }), recur_arity)
      end

      def with_recur(arity)
        Scope.new(locals, arity)
      end
    end
    Scope::EMPTY = Scope.new({}.freeze, nil)

    def initialize(runtime)
      @runtime = runtime
    end

    # `tail` marks a position whose value is returned directly by the
    # enclosing loop*/fn body - the only place recur is allowed.
    def analyze(form, scope = Scope::EMPTY, tail: false)
      case form
      when Symbol then analyze_symbol(form, scope)
      when ISeq then form.empty? ? Nodes::Const.new(List::EMPTY) : analyze_seq(form, scope, tail)
      when Vector then Nodes::VectorNode.new(analyze_all(form, scope))
      when Set then Nodes::SetNode.new(analyze_all(form, scope))
      when Map then Nodes::MapNode.new(form.map { |k, v| [analyze(k, scope), analyze(v, scope)] })
      else Nodes::Const.new(form)
      end
    end

    # Expands form once if it is a macro call, a syntax-quote or interop
    # shorthand; otherwise returns it unchanged.
    def macroexpand_1(form, scope = Scope::EMPTY)
      return form unless form.is_a?(ISeq) && !form.empty?

      head = form.first
      return SyntaxQuote.new(@runtime).expand(form.to_a[1]) if head == SYNTAX_QUOTE

      # Like Clojure, macros win over interop shorthands (e.g. `..`).
      macro = macro_var(head, scope)
      return expand_macro(macro, form, scope) if macro

      expand_host_shorthand(form, scope) || form
    end

    # Clojure's ns-resolve: the var or Ruby constant symbol names in ns, or nil.
    def resolve_in(ns, symbol)
      var = lookup_var(symbol, ns)
      return var if var

      constant = host_constant(symbol, ns)
      constant.equal?(Host::NOT_FOUND) ? nil : constant
    end

    def macroexpand(form, scope = Scope::EMPTY)
      loop do
        expanded = macroexpand_1(form, scope)
        return expanded if expanded.equal?(form)

        form = expanded
      end
    end

    private

    def analyze_all(forms, scope)
      forms.map { |form| analyze(form, scope) }
    end

    def analyze_symbol(symbol, scope)
      if symbol.ns.nil? && (binding = scope.locals[symbol.name])
        return Nodes::Local.new(binding)
      end

      var = lookup_var(symbol)
      if var
        check_public(var)
        raise CompilerError, "Can't take value of a macro: #{var}" if var.macro?

        return Nodes::VarRef.new(var)
      end

      constant = host_constant(symbol)
      if constant.equal?(Host::NOT_FOUND)
        raise CompilerError, "No such var: #{symbol}" if symbol.ns && @runtime.resolve_namespace(symbol.ns)

        raise CompilerError, "Unable to resolve symbol: #{symbol} in this context"
      end

      Nodes::Const.new(constant)
    end

    # `String`, `File::Stat` => the Ruby constant; `Math/PI` => Math::PI.
    # Namespaces and aliases win over Ruby modules of the same name.
    def host_constant(symbol, ns = @runtime.current_ns)
      return Host.constant(symbol.name) unless symbol.ns
      return Host::NOT_FOUND if namespace_for(symbol, ns) || !Host.module?(symbol.ns)

      Host.constant("#{symbol.ns}::#{symbol.name}")
    end

    #   (.method target args*)  => (. target method args*)
    #   (.-attr target)         => (. target -attr)
    #   (Class. args*)          => (new Class args*)
    #   (Class/method args*)    => (. Class method args*)
    def expand_host_shorthand(form, scope)
      head = form.first
      return nil unless head.is_a?(Symbol)

      args = form.to_a.drop(1)
      if head.ns.nil? && head.name.start_with?(".") && head.name.size > 1 && !scope.locals.key?(head.name)
        raise CompilerError, "Malformed member expression, expecting (#{head} target ...)" if args.empty?

        List[DOT, args.first, Symbol.new(nil, head.name[1..]), *args.drop(1)]
      elsif head.ns.nil? && head.name.end_with?(".") && head.name.size > 1 && !scope.locals.key?(head.name)
        List[NEW, Symbol.new(nil, head.name.chomp(".")), *args]
      elsif head.ns && namespace_for(head).nil? && Host.module?(head.ns)
        List[DOT, Symbol.new(nil, head.ns), Symbol.new(nil, head.name), *args]
      end
    end

    def resolve_var(symbol)
      lookup_var(symbol) or raise CompilerError, "Unable to resolve symbol: #{symbol} in this context"
    end

    # Like Clojure's lookupVar: a qualified symbol names a var interned in
    # that namespace (or alias); an unqualified one, any mapping in ns.
    def lookup_var(symbol, ns = @runtime.current_ns)
      if symbol.ns
        namespace_for(symbol, ns)&.own_var(symbol.name)
      else
        ns.find_var(symbol.name)
      end
    end

    def namespace_for(symbol, ns = @runtime.current_ns)
      ns.lookup_alias(symbol.ns) || @runtime.find_namespace(symbol.ns)
    end

    def check_public(var)
      return unless var.private? && !var.ns.equal?(@runtime.current_ns)

      raise CompilerError, "var: #{var} is not public"
    end

    # The macro Var named by head, unless head is a special form or a
    # local (locals shadow macros).
    def macro_var(head, scope)
      return nil unless head.is_a?(Symbol)
      return nil if head.ns.nil? && (SPECIAL_FORMS.include?(head.name) || scope.locals.key?(head.name))

      var = lookup_var(head)
      return nil unless var&.macro?

      check_public(var)
      var
    end

    # Macros are fns taking the whole form and the local environment
    # (&form, &env) before their declared arguments.
    def expand_macro(var, form, scope)
      env = Map.new(scope.locals.to_h { |name, binding| [Symbol.new(nil, name), binding] })
      RClojure.invoke(var.deref, [form, env, *form.to_a.drop(1)])
    rescue CompilerError
      raise
    rescue StandardError => e
      raise CompilerError, "Error macroexpanding #{form.first}: #{e.message}"
    end

    def analyze_seq(form, scope, tail)
      head = form.first
      args = form.to_a.drop(1)
      if head.is_a?(Symbol) && head.ns.nil? && SPECIAL_FORMS.include?(head.name)
        method = head.name == "." ? :analyze_dot : :"analyze_#{head.name.delete('*')}"
        return send(method, args, scope, tail)
      end

      expanded = macroexpand_1(form, scope)
      return analyze(expanded, scope, tail: tail) unless expanded.equal?(form)

      Nodes::Invoke.new(analyze(head, scope), analyze_all(args, scope))
    end

    # (. target method args*), (. target (method args*)) or (. target -attr).
    # `& f` after the args passes f as the Ruby block.
    def analyze_dot(args, scope, _tail)
      raise CompilerError, "Malformed member expression, expecting (. target member ...)" if args.size < 2

      target, member, *call_args = args
      if member.is_a?(ISeq) && !member.empty?
        call_args = member.rest.to_a
        member = member.first
      end
      unless member.is_a?(Symbol) && member.ns.nil?
        raise CompilerError, "Malformed member expression, member must be a symbol: #{Printer.pr_str(member)}"
      end

      if member.name.start_with?("-")
        raise CompilerError, "Attribute access (#{member}) takes no arguments" unless call_args.empty?

        member = Symbol.new(nil, member.name[1..])
      end
      host_call(analyze(target, scope), Host.method_name(member.name), call_args, scope)
    end

    # (new Class args*), with an optional `& f` block like `.` calls.
    def analyze_new(args, scope, _tail)
      class_name = args.first
      klass = class_name.is_a?(Symbol) ? host_constant(class_name) : Host::NOT_FOUND
      unless klass.is_a?(Class)
        raise CompilerError, "Unable to resolve classname: #{Printer.pr_str(class_name)}"
      end

      host_call(Nodes::Const.new(klass), :new, args.drop(1), scope)
    end

    def host_call(target_node, method, call_args, scope)
      amp = call_args.index(AMPERSAND)
      block = nil
      if amp
        unless call_args.size == amp + 2
          raise CompilerError, "& in a host call must be followed by exactly one block fn"
        end

        block = analyze(call_args.last, scope)
        call_args = call_args.first(amp)
      end
      Nodes::HostCall.new(target_node, method, analyze_all(call_args, scope), block)
    end

    # (set! (. target attr) value) calls the Ruby setter `attr=`; also
    # accepts the (.attr target) and (.-attr target) shorthands.
    def analyze_set!(args, scope, _tail)
      raise CompilerError, "Malformed assignment, expecting (set! target val)" unless args.size == 2

      place, value = args
      case place
      when Symbol
        if place.ns.nil? && scope.locals.key?(place.name)
          raise CompilerError, "Cannot assign to non-mutable: #{place}"
        end

        # Clojure only allows set! on vars with a thread binding, and
        # rclojure has no dynamic vars yet.
        raise CompilerError, "Can't change/establish root binding of: #{resolve_var(place)} with set"
      when ISeq
        call = analyze(place, scope)
        unless call.is_a?(Nodes::HostCall) && call.args.empty? && call.block.nil? && call.method != :new
          raise CompilerError, "Invalid assignment target: #{Printer.pr_str(place)}"
        end

        Nodes::HostAssign.new(call.target, :"#{call.method}=", analyze(value, scope))
      else raise CompilerError, "Invalid assignment target: #{Printer.pr_str(place)}"
      end
    end

    def analyze_def(args, scope, _tail)
      name = args.first
      unless name.is_a?(Symbol) && (name.ns.nil? || name.ns == @runtime.current_ns.name)
        raise CompilerError, "First argument to def must be an unqualified symbol"
      end

      init = case args.size
             when 1 then nil
             when 2 then args[1]
             when 3
               raise CompilerError, "Docstring passed to def must be a string" unless args[1].is_a?(::String)

               args[2]
             else raise CompilerError, "Too many arguments to def"
             end

      # Interned before analyzing init, so the init can refer to the var
      # itself (e.g. a recursive function).
      var = @runtime.current_ns.intern(name.name)
      init_node = args.size == 1 ? nil : analyze(init, scope)
      # Unnamed fns take the var's name, for error messages and printing.
      init_node.name = var.to_s.delete_prefix("#'") if init_node.is_a?(Nodes::FnNode) && init_node.name.nil?
      Nodes::Def.new(var, init_node)
    end

    def analyze_if(args, scope, tail)
      raise CompilerError, "Too few arguments to if" if args.size < 2
      raise CompilerError, "Too many arguments to if" if args.size > 3

      Nodes::If.new(analyze(args[0], scope),
                    analyze(args[1], scope, tail: tail),
                    args.size == 3 ? analyze(args[2], scope, tail: tail) : NIL_NODE)
    end

    def analyze_do(args, scope, tail)
      analyze_body(args, scope, tail)
    end

    def analyze_body(forms, scope, tail)
      return NIL_NODE if forms.empty?

      *statements, ret = forms
      Nodes::Do.new(analyze_all(statements, scope), analyze(ret, scope, tail: tail))
    end

    def analyze_let(args, scope, tail)
      bindings, scope = analyze_bindings("let*", args, scope)
      Nodes::Let.new(bindings, analyze_body(args.drop(1), scope, tail))
    end

    def analyze_loop(args, scope, _tail)
      bindings, scope = analyze_bindings("loop*", args, scope)
      body = analyze_body(args.drop(1), scope.with_recur(bindings.size), true)
      Nodes::Loop.new(bindings, body)
    end

    # Returns [[[LocalBinding, init_node], ...], scope_with_all_bindings].
    def analyze_bindings(form_name, args, scope)
      vector = args.first
      raise CompilerError, "#{form_name} requires a vector for its binding" unless vector.is_a?(Vector)
      raise CompilerError, "#{form_name} requires an even number of forms in binding vector" if vector.size.odd?

      bindings = vector.each_slice(2).map do |name, init|
        binding = LocalBinding.new(local_name(name, form_name))
        # Each init sees the bindings before it, but recur is never valid here.
        node = analyze(init, scope)
        scope = scope.with_locals([binding])
        [binding, node]
      end
      [bindings, scope]
    end

    def local_name(symbol, form_name)
      unless symbol.is_a?(Symbol) && symbol.ns.nil? && symbol != AMPERSAND
        raise CompilerError, "Bad binding form in #{form_name}, expected unqualified symbol, got: #{Printer.pr_str(symbol)}"
      end

      symbol.name
    end

    def analyze_recur(args, scope, tail)
      raise CompilerError, "Cannot recur across try" if scope.recur_arity == :try
      raise CompilerError, "Can only recur from tail position" unless tail && scope.recur_arity

      if args.size != scope.recur_arity
        raise CompilerError,
              "Mismatched argument count to recur, expected: #{scope.recur_arity} args, got: #{args.size}"
      end

      Nodes::RecurNode.new(analyze_all(args, scope))
    end

    def analyze_quote(args, _scope, _tail)
      raise CompilerError, "Wrong number of args (#{args.size}) passed to quote" unless args.size == 1

      Nodes::Const.new(args.first)
    end

    def analyze_var(args, _scope, _tail)
      unless args.size == 1 && args.first.is_a?(Symbol)
        raise CompilerError, "var expects a single symbol"
      end

      Nodes::TheVar.new(resolve_var(args.first))
    end

    def analyze_throw(args, scope, _tail)
      raise CompilerError, "Too many arguments to throw, throw expects a single exception" unless args.size == 1

      Nodes::Throw.new(analyze(args.first, scope))
    end

    # (fn* name? [params*] body*) or (fn* name? ([params*] body*)+)
    def analyze_fn(args, scope, _tail)
      name = args.first.is_a?(Symbol) ? args.shift : nil
      self_binding = name && LocalBinding.new(local_name(name, "fn*"))
      scope = scope.with_locals([self_binding]) if self_binding

      method_forms = args.first.is_a?(Vector) ? [List.from(args)] : args
      raise CompilerError, "fn* requires a parameter vector" if method_forms.empty?

      methods = method_forms.map do |method_form|
        unless method_form.is_a?(ISeq) && method_form.first.is_a?(Vector)
          raise CompilerError, "Invalid fn* method, expected ([params*] body*), got: #{Printer.pr_str(method_form)}"
        end

        analyze_fn_method(method_form.first, method_form.rest.to_a, scope)
      end
      check_arities(methods)

      Nodes::FnNode.new(name&.name, self_binding, methods)
    end

    def analyze_fn_method(param_vector, body, scope)
      params = param_vector.to_a
      rest = nil
      if (amp = params.index(AMPERSAND))
        if params.size != amp + 2
          raise CompilerError, "Invalid parameter list, & must be followed by exactly one symbol"
        end

        rest = LocalBinding.new(local_name(params[amp + 1], "fn*"))
        params = params.first(amp)
      end
      bindings = params.map { |param| LocalBinding.new(local_name(param, "fn*")) }

      all = rest ? bindings + [rest] : bindings
      body_scope = scope.with_locals(all).with_recur(all.size)
      Nodes::FnMethod.new(bindings, rest, analyze_body(body, body_scope, true))
    end

    def check_arities(methods)
      variadic, fixed = methods.partition(&:rest)
      raise CompilerError, "Can't have more than 1 variadic overload" if variadic.size > 1
      if fixed.map(&:required).uniq.size != fixed.size
        raise CompilerError, "Can't have 2 overloads with same arity"
      end
      return unless variadic.any? && fixed.any? { |m| m.required > variadic.first.required }

      raise CompilerError, "Can't have fixed arity function with more params than variadic function"
    end

    # (try body* (catch Class name body*)* (finally body*)?)
    def analyze_try(args, scope, _tail)
      body_forms = args.take_while { |form| !clause?(form, CATCH) && !clause?(form, FINALLY) }
      clauses = args.drop(body_forms.size)
      finally_form = clauses.last if clause?(clauses.last, FINALLY)
      catch_forms = finally_form ? clauses[0...-1] : clauses
      unless catch_forms.all? { |form| clause?(form, CATCH) }
        raise CompilerError, "Only catch or finally clause can follow catch in try expression"
      end

      try_scope = scope.with_recur(:try)
      body = analyze_body(body_forms, try_scope, false)
      catches = catch_forms.map { |form| analyze_catch(form.rest.to_a, try_scope) }
      finally = finally_form && analyze_body(finally_form.rest.to_a, try_scope, false)
      Nodes::Try.new(body, catches, finally)
    end

    def clause?(form, symbol)
      form.is_a?(ISeq) && form.first == symbol
    end

    def analyze_catch(args, scope)
      raise CompilerError, "catch requires a class and a binding name" if args.size < 2

      klass = resolve_exception_class(args[0])
      binding = LocalBinding.new(local_name(args[1], "catch"))
      Nodes::Catch.new(klass, binding, analyze_body(args.drop(2), scope.with_locals([binding]), false))
    end

    # `:default` catches anything; otherwise a Ruby exception class name,
    # looked up at top level first, then inside RClojure (e.g. ExceptionInfo).
    def resolve_exception_class(form)
      return Object if form == :default
      raise CompilerError, "Unable to resolve classname: #{Printer.pr_str(form)}" unless form.is_a?(Symbol) && form.ns.nil?

      [Object, RClojure].each do |namespace|
        klass = begin
          namespace.const_get(form.name)
        rescue NameError
          nil
        end
        return klass if klass.is_a?(Class) && klass <= Exception
      end

      raise CompilerError, "Unable to resolve classname: #{form}"
    end
  end
end
