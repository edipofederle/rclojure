module RClojure
  # A function created by fn*.
  class Fn
    attr_reader :name

    def initialize(name, methods, closure)
      @name = name
      @closure = closure
      @fixed = {}
      @variadic = nil
      methods.each { |m| m.rest ? @variadic = m : @fixed[m.required] = m }
    end

    def call(*args)
      method = @fixed[args.size] || (@variadic if @variadic && args.size >= @variadic.required)
      raise ArityError, "Wrong number of args (#{args.size}) passed to: #{name || 'fn'}" unless method

      values = args.first(method.required)
      if method.rest
        extra = args.drop(method.required)
        values << (extra.empty? ? nil : ArraySeq.new(extra, 0))
      end

      loop do
        frame = Env.new(@closure)
        method.params.each_with_index { |binding, i| frame[binding] = values[i] }
        frame[method.rest] = values.last if method.rest
        result = method.body.eval(frame)
        return result unless result.is_a?(Nodes::Recur)

        # recur supplies the rest param directly, as a single seq argument.
        values = result.args
      end
    end

    def to_proc
      method(:call).to_proc
    end

    def inspect
      "#<RClojure::Fn #{name || 'anonymous'}>"
    end
  end

  # A function implemented in Ruby, wrapping a lambda.
  class Builtin
    attr_reader :name

    def initialize(name, impl)
      @name = name
      @impl = impl
      kinds = impl.parameters.map(&:first)
      @min_args = kinds.count(:req)
      @max_args = kinds.include?(:rest) ? Float::INFINITY : @min_args + kinds.count(:opt)
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
