module RClojure
  # A function created by fn*: one callable per fixed arity, plus at most
  # one variadic callable taking the required args and then the rest as a
  # seq (or nil).
  class Fn
    attr_reader :name

    def initialize(name, fixed, required = nil, variadic = nil)
      @name = name
      @fixed = fixed
      @required = required
      @variadic = variadic
      @arity0, @arity1, @arity2, @arity3 = fixed.values_at(0, 1, 2, 3)
    end

    # Like Clojure's IFn invoke overloads: compiled calls with up to three
    # args go straight to the matching arity, without splatting args.
    def call0
      @arity0 ? @arity0.call : call
    end

    def call1(a)
      @arity1 ? @arity1.call(a) : call(a)
    end

    def call2(a, b)
      @arity2 ? @arity2.call(a, b) : call(a, b)
    end

    def call3(a, b, c)
      @arity3 ? @arity3.call(a, b, c) : call(a, b, c)
    end

    def call(*args)
      impl = @fixed[args.size]
      return impl.call(*args) if impl

      unless @variadic && args.size >= @required
        raise ArityError, "Wrong number of args (#{args.size}) passed to: #{name || 'fn'}"
      end

      rest = args.size > @required ? ArraySeq.new(args.drop(@required), 0) : nil
      @variadic.call(*args.first(@required), rest)
    end

    # Lets Ruby code pass an rclojure fn as a block: `xs.map(&fn)`.
    def to_proc
      method(:call).to_proc
    end

    def inspect
      "#<RClojure::Fn #{name || 'anonymous'}>"
    end
  end

  # A function implemented in Ruby, wrapping a lambda. fast maps arg
  # counts (0-3) to lambdas taking exactly that many args, used by callN;
  # impl itself is one when its arity is fixed.
  class Builtin
    attr_reader :name

    def initialize(name, impl, fast = {})
      @name = name
      @impl = impl
      kinds = impl.parameters.map(&:first)
      @min_args = kinds.count(:req)
      @max_args = kinds.include?(:rest) ? Float::INFINITY : @min_args + kinds.count(:opt)
      fast = { @min_args => impl }.merge(fast) if @min_args == @max_args
      @arity0, @arity1, @arity2, @arity3 = fast.values_at(0, 1, 2, 3)
    end

    def call0
      @arity0 ? @arity0.call : call
    end

    def call1(a)
      @arity1 ? @arity1.call(a) : call(a)
    end

    def call2(a, b)
      @arity2 ? @arity2.call(a, b) : call(a, b)
    end

    def call3(a, b, c)
      @arity3 ? @arity3.call(a, b, c) : call(a, b, c)
    end

    def call(*args)
      unless args.size.between?(@min_args, @max_args)
        raise ArityError, "Wrong number of args (#{args.size}) passed to: #{name}"
      end

      @impl.call(*args)
    end

    def to_proc
      @impl
    end

    def inspect
      "#<RClojure::Builtin #{name}>"
    end
  end
end
