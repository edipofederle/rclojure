module RClojure
  module Core
    module Numbers
      module_function

      def install(ns)
        define = ->(name, impl) { Core.define(ns, name, impl) }

        define.("+", lambda { |*nums|
          return normalize(nums[0] + nums[1]) if nums.size == 2 # fast path for the common case

          normalize(nums.reduce(0, :+))
        })
        define.("*", ->(*nums) { normalize(nums.reduce(1, :*)) })
        define.("-", ->(x, *nums) { normalize(nums.empty? ? -x : nums.reduce(x, :-)) })
        define.("/", lambda { |x, *nums|
          nums.empty? ? divide(1, x) : nums.reduce(x) { |acc, n| divide(acc, n) }
        })
        define.("inc", ->(x) { x + 1 })
        define.("dec", ->(x) { x - 1 })
        define.("quot", ->(num, div) { truncating(num, div) })
        define.("rem", ->(num, div) { normalize(num.remainder(div)) })
        define.("mod", ->(num, div) { normalize(num.modulo(div)) })
        define.("max", ->(x, *more) { [x, *more].max })
        define.("min", ->(x, *more) { [x, *more].min })
        define.("abs", ->(x) { x.abs })

        { "<" => :<, ">" => :>, "<=" => :<=, ">=" => :>= }.each do |name, op|
          define.(name, lambda { |x, *nums|
            return x.public_send(op, nums[0]) if nums.size == 1 # fast path for the common case

            prev = x
            nums.all? { |n| prev.public_send(op, n).tap { prev = n } }
          })
        end
        define.("==", ->(x, *nums) { nums.all? { |n| n == x } })

        define.("zero?", ->(x) { x.zero? })
        define.("pos?", ->(x) { x.positive? })
        define.("neg?", ->(x) { x.negative? })
        define.("even?", ->(x) { integer!(x).even? })
        define.("odd?", ->(x) { integer!(x).odd? })

        define.("number?", ->(x) { x.is_a?(Numeric) })
        define.("integer?", ->(x) { x.is_a?(Integer) })
        define.("float?", ->(x) { x.is_a?(Float) })
        define.("ratio?", ->(x) { x.is_a?(Rational) })
        define.("rational?", ->(x) { x.is_a?(Integer) || x.is_a?(Rational) })
      end

      # Integer division yields a ratio, like Clojure: (/ 1 2) => 1/2
      def divide(a, b)
        a.is_a?(Float) || b.is_a?(Float) ? a / b : normalize(a.to_r / b)
      end

      # Clojure's quot truncates toward zero; Ruby's / floors.
      def truncating(num, div)
        quotient = num.is_a?(Float) || div.is_a?(Float) ? (num / div).truncate.to_f : (num.to_r / div).truncate
        normalize(quotient)
      end

      # Ratios with a denominator of 1 become plain integers.
      def normalize(number)
        number.is_a?(Rational) && number.denominator == 1 ? number.numerator : number
      end

      def integer!(x)
        raise ArgumentError, "Argument must be an integer: #{Printer.pr_str(x)}" unless x.is_a?(Integer)

        x
      end
    end
  end
end
