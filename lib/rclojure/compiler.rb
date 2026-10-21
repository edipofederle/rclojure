module RClojure
  # Compiles analyzed nodes to Ruby source, the way ClojureScript's
  # compiler emits JavaScript, then evaluates it. A top-level form becomes
  # a lambda taking the constants array `k` (Vars, quoted data, classes,
  # strings, ...); locals become uniquely named Ruby locals.
  #
  # Ruby's truthiness is Clojure's (only nil and false are falsy), so `if`
  # is a plain conditional. loop* and fns that recur become `while true`
  # loops: tail positions `break` with their value, and recur reassigns
  # the loop's locals and goes round again with `next`.
  class Compiler
    # Runs the Ruby source compile returned, with its constants.
    def self.run(source, constants)
      RubyVM::InstructionSequence.compile(source, "(rclojure)").eval.call(constants)
    end

    def self.throw!(value)
      raise Error, "Cannot throw #{Printer.pr_str(value)}: not an exception" unless value.is_a?(Exception)

      raise value
    end

    def initialize
      @constants = []
      @constant_indexes = {}.compare_by_identity
      @names = {}.compare_by_identity
      @counter = 0
      # Locals declared inside the enclosing loops (up to the nearest fn),
      # whose Ruby variables are reassigned as the loop goes round; see
      # compile_fn. nil outside loops.
      @loop_locals = nil
      # The locals a recur in tail position reassigns.
      @recur_target = nil
    end

    # [Ruby source of a lambda taking the constants, the constants]
    def compile(node)
      ["->(k) {\n#{expr(node)}\n}", @constants]
    end

    private

    # Ruby expression for node's value.
    def expr(node)
      case node
      when Nodes::Const then literal(node.value)
      when Nodes::Local then name(node.binding)
      when Nodes::VarRef then "#{constant(node.var)}.deref"
      when Nodes::TheVar then constant(node.var)
      when Nodes::Def then node.init ? "#{constant(node.var)}.bind_root(#{expr(node.init)})" : constant(node.var)
      when Nodes::If then "(#{expr(node.test)} ? (#{expr(node.then_branch)}) : (#{expr(node.else_branch)}))"
      when Nodes::Do then "(#{(node.statements.map { |s| expr(s) } << expr(node.ret)).join("\n")})"
      when Nodes::Let then "(#{bind(node.bindings)}\n#{expr(node.body)})"
      when Nodes::Loop then compile_loop(node)
      when Nodes::FnNode then compile_fn(node)
      when Nodes::Invoke then compile_invoke(node)
      when Nodes::HostCall then compile_host_call(node)
      when Nodes::HostAssign then compile_host_assign(node)
      when Nodes::VectorNode then "RClojure::Vector.new([#{list(node.items)}])"
      when Nodes::MapNode then "RClojure::Map.new({#{node.pairs.map { |k, v| "#{expr(k)} => #{expr(v)}" }.join(', ')}})"
      when Nodes::SetNode then "RClojure::Set.new([#{list(node.items)}])"
      when Nodes::Throw then "RClojure::Compiler.throw!(#{expr(node.exception)})"
      when Nodes::Try then compile_try(node)
      else raise CompilerError, "Can't compile #{node.class}"
      end
    end

    # Ruby statements for node in tail position of a loop: they `break`
    # with the value, or `next` after a recur.
    def tail(node)
      case node
      when Nodes::If then "if #{expr(node.test)}\n#{tail(node.then_branch)}\nelse\n#{tail(node.else_branch)}\nend"
      when Nodes::Do then (node.statements.map { |s| expr(s) } << tail(node.ret)).join("\n")
      when Nodes::Let then "#{bind(node.bindings)}\n#{tail(node.body)}"
      when Nodes::RecurNode then compile_recur(node)
      else "break #{expr(node)}"
      end
    end

    def list(nodes)
      nodes.map { |node| expr(node) }.join(", ")
    end

    def bind(bindings)
      bindings.map do |binding, init|
        @loop_locals[binding] = true if @loop_locals
        "#{name(binding)} = #{expr(init)}"
      end.join("\n")
    end

    def compile_loop(node)
      outer_locals = @loop_locals
      outer_target = @recur_target
      inits = bind(node.bindings)
      @loop_locals = (outer_locals || {}.compare_by_identity).dup
      node.bindings.each { |binding, _| @loop_locals[binding] = true }
      @recur_target = node.bindings.map(&:first)
      "(#{inits}\nwhile true\n#{tail(node.body)}\nend)"
    ensure
      @loop_locals = outer_locals
      @recur_target = outer_target
    end

    # Evaluates every arg before reassigning any local, as they may use them.
    def compile_recur(node)
      temps = node.args.map { |arg| ["__t#{@counter += 1}", expr(arg)] }
      [*temps.map { |temp, value| "#{temp} = #{value}" },
       *@recur_target.zip(temps).map { |binding, (temp, _)| "#{name(binding)} = #{temp}" },
       "next"].join("\n")
    end

    # A Fn with a lambda per arity. Ruby closures capture variables, not
    # values, so a fn created inside a loop that uses the loop's locals
    # (or names itself) would see them change as the loop goes round. Like
    # ClojureScript, such a fn is wrapped in a lambda called right away
    # with those locals, which its arity lambdas then capture instead.
    def compile_fn(node)
      outer_locals = @loop_locals
      captured = outer_locals ? loop_locals_used(node, outer_locals) : []
      fixed = []
      variadic = nil
      node.methods.each do |method|
        source = compile_method(method)
        method.rest ? variadic = [method.required, source] : fixed << [method.required, source]
      end
      fn = "RClojure::Fn.new(#{node.name.inspect}, {#{fixed.map { |n, src| "#{n} => #{src}" }.join(",\n")}}" \
           "#{variadic && ", #{variadic[0]}, #{variadic[1]}"})"
      fn = "(#{name(node.self_binding)} = #{fn})" if node.self_binding
      return fn unless outer_locals && (captured.any? || node.self_binding)

      names = captured.map { |binding| name(binding) }.join(", ")
      "->(#{names}) {\n#{fn}\n}.(#{names})"
    ensure
      @loop_locals = outer_locals
    end

    def compile_method(method)
      params = method.params + (method.rest ? [method.rest] : [])
      outer_target = @recur_target
      if contains_recur?(method.body)
        @loop_locals = params.to_h { |param| [param, true] }.compare_by_identity
        @recur_target = params
        body = "while true\n#{tail(method.body)}\nend"
      else
        @loop_locals = nil
        body = expr(method.body)
      end
      "->(#{params.map { |param| name(param) }.join(', ')}) {\n#{body}\n}"
    ensure
      @recur_target = outer_target
    end

    def compile_invoke(node)
      fn = expr(node.fn)
      return "RClojure.invoke(#{fn}, [#{list(node.args)}])" if node.args.size > 3

      "RClojure.invoke#{node.args.size}(#{[fn, *node.args.map { |arg| expr(arg) }].join(', ')})"
    end

    def compile_host_call(node)
      receiver = "(#{expr(node.target)})"
      args = node.args.map { |arg| expr(arg) }
      args << "&RClojure::Host.block(#{expr(node.block)})" if node.block
      if node.method.match?(/\A[a-z_][a-zA-Z0-9_]*[?!]?\z/)
        "#{receiver}.#{node.method}(#{args.join(', ')})"
      else
        "#{receiver}.public_send(#{[node.method.inspect, *args].join(', ')})"
      end
    end

    def compile_host_assign(node)
      receiver = "__t#{@counter += 1}"
      value = "__t#{@counter += 1}"
      "(#{receiver} = #{expr(node.target)}\n#{value} = #{expr(node.value)}\n" \
        "#{receiver}.public_send(#{node.setter.inspect}, #{value})\n#{value})"
    end

    # `case` matches the catch clauses with ===, as Try#eval does.
    def compile_try(node)
      exception = "__e#{@counter += 1}"
      clauses = node.catches.map do |clause|
        @loop_locals[clause.binding] = true if @loop_locals
        "when #{constant(clause.klass)}\n#{name(clause.binding)} = #{exception}\n#{expr(clause.body)}"
      end
      rescue_part = clauses.empty? ? "" : "rescue ::Exception => #{exception}\ncase #{exception}\n#{clauses.join("\n")}\nelse raise\nend\n"
      ensure_part = node.finally ? "ensure\n#{expr(node.finally)}\n" : ""
      "begin\n#{expr(node.body)}\n#{rescue_part}#{ensure_part}end"
    end

    def literal(value)
      case value
      when nil, true, false then value.inspect
      when Integer then value.negative? ? "(#{value})" : value.to_s
      when Float then value.finite? ? "(#{value.inspect})" : constant(value)
      when ::Symbol then value.inspect
      else constant(value)
      end
    end

    def constant(value)
      index = @constant_indexes[value] ||= (@constants << value).size - 1
      "k[#{index}]"
    end

    # A Ruby local name per binding, unique within the compiled form.
    def name(binding)
      @names[binding] ||= "l_#{binding.name.gsub(/[^a-zA-Z0-9_]/) { |c| c == '-' ? '_' : "_#{c.ord}_" }}__#{@counter += 1}"
    end

    # Whether a recur in body targets body's fn method (recurs inside a
    # nested loop* or fn* target those instead).
    def contains_recur?(body)
      each_node(body, prune: [Nodes::Loop, Nodes::FnNode]).any? { |node| node.is_a?(Nodes::RecurNode) }
    end

    def loop_locals_used(fn_node, loop_locals)
      each_node(fn_node).filter_map do |node|
        node.binding if node.is_a?(Nodes::Local) && loop_locals.key?(node.binding)
      end.uniq
    end

    # Every node in the tree under (and including) value. Nodes of the
    # prune classes are yielded but not entered.
    def each_node(value, prune: [], &block)
      return enum_for(:each_node, value, prune: prune) unless block

      case value
      when Array then value.each { |item| each_node(item, prune: prune, &block) }
      when Struct
        return unless value.class.name&.start_with?("RClojure::Nodes::")

        yield value
        return if value.is_a?(Nodes::Const) || prune.any? { |klass| value.is_a?(klass) }

        value.each { |member| each_node(member, prune: prune, &block) }
      end
    end
  end
end
