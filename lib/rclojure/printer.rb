module RClojure
  # Turns rclojure data into text. `pr_str` is readable (strings quoted,
  # like Clojure's pr-str); `print_str` is for humans (like print-str).
  module Printer
    STRING_ESCAPES = { "\n" => "\\n", "\t" => "\\t", "\r" => "\\r", "\b" => "\\b",
                       "\f" => "\\f", '"' => '\\"', "\\" => "\\\\" }.freeze

    module_function

    def pr_str(value)
      write(value, true)
    end

    def print_str(value)
      write(value, false)
    end

    # Clojure's `str` of a single value.
    def str(value)
      case value
      when nil then ""
      when ::String then value
      else pr_str(value)
      end
    end

    def write(value, readably)
      case value
      when nil then "nil"
      when true then "true"
      when false then "false"
      when ::String then readably ? "\"#{value.gsub(/[\n\t\r\b\f"\\]/, STRING_ESCAPES)}\"" : value
      when ::Symbol then ":#{value}"
      when Rational then value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
      when Numeric, Symbol then value.to_s
      when List then "(#{write_all(value, readably)})"
      when Vector then "[#{write_all(value, readably)}]"
      when Map then "{#{value.map { |k, v| "#{write(k, readably)} #{write(v, readably)}" }.join(', ')}}"
      when Set then "\#{#{write_all(value, readably)}}"
      when Var then value.to_s
      when Fn, Builtin then "#<fn #{value.name || 'anonymous'}>"
      when Atom then "#<Atom #{write(value.deref, readably)}>"
      when ExceptionInfo then "#<ExceptionInfo #{write(value.message, true)} #{write(value.data, true)}>"
      when Exception then "#<#{value.class} #{write(value.message, true)}>"
      when Class, Module then value.name
      else value.inspect
      end
    end

    def write_all(values, readably)
      values.map { |v| write(v, readably) }.join(" ")
    end
  end
end
