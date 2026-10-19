module RClojure
  # Calls anything callable. Keywords look themselves up: `(:a m)`.
  def self.invoke(fn, args)
    case fn
    when ::Symbol
      unless args.size.between?(1, 2)
        raise ArityError, "Wrong number of args (#{args.size}) passed to: #{Printer.pr_str(fn)}"
      end

      get(args[0], fn, args[1])
    else
      raise Error, "#{Printer.pr_str(fn)} is not a function" unless fn.respond_to?(:call)

      fn.call(*args)
    end
  end

  def self.get(coll, key, default = nil)
    case coll
    when Map then coll.key?(key) ? coll[key] : default
    when Set then coll.include?(key) ? key : default
    when Vector then key.is_a?(Integer) && key.between?(0, coll.size - 1) ? coll[key] : default
    else default
    end
  end

  # Clojure's `=`: like Ruby's ==, except integers/ratios never equal floats.
  def self.equiv?(a, b)
    if a.is_a?(Numeric) && b.is_a?(Numeric)
      a.is_a?(Float) == b.is_a?(Float) && a == b
    else
      a == b
    end
  end

  # Primitive functions implemented in Ruby. The rest of clojure.core will
  # be written in rclojure itself once macros exist.
  module Core
    module_function

    def install(ns)
      define(ns, "+", lambda { |*nums|
        return normalize(nums[0] + nums[1]) if nums.size == 2 # fast path for the common case

        normalize(nums.reduce(0, :+))
      })
      define(ns, "*", ->(*nums) { normalize(nums.reduce(1, :*)) })
      define(ns, "-", lambda { |x, *nums|
        normalize(nums.empty? ? -x : nums.reduce(x, :-))
      })
      define(ns, "/", lambda { |x, *nums|
        nums.empty? ? divide(1, x) : nums.reduce(x) { |acc, n| divide(acc, n) }
      })

      { "<" => :<, ">" => :>, "<=" => :<=, ">=" => :>= }.each do |name, op|
        define(ns, name, lambda { |x, *nums|
          return x.public_send(op, nums[0]) if nums.size == 1 # fast path for the common case

          prev = x
          nums.all? { |n| prev.public_send(op, n).tap { prev = n } }
        })
      end

      define(ns, "=", ->(x, *more) { [x, *more].each_cons(2).all? { |a, b| RClojure.equiv?(a, b) } })
      define(ns, "not=", ->(x, *more) { ![x, *more].each_cons(2).all? { |a, b| RClojure.equiv?(a, b) } })

      define(ns, "ex-info", ->(message, data, cause = nil) { ExceptionInfo.new(message, data, cause) })
      define(ns, "ex-data", ->(ex) { ex.respond_to?(:data) ? ex.data : nil })
      define(ns, "ex-message", ->(ex) { ex.is_a?(Exception) ? ex.message : nil })
    end

    def define(ns, name, impl)
      ns.intern(name).bind_root(Builtin.new("#{ns.name}/#{name}", impl))
    end

    # Integer division yields a ratio, like Clojure: (/ 1 2) => 1/2
    def divide(a, b)
      a.is_a?(Float) || b.is_a?(Float) ? a / b : normalize(a.to_r / b)
    end

    # Ratios with a denominator of 1 become plain integers.
    def normalize(number)
      number.is_a?(Rational) && number.denominator == 1 ? number.numerator : number
    end
  end
end
