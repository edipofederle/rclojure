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

    # Clojure's `str` of a single value: a Ruby object the printer doesn't
    # know gives its `to_s` (Java's toString), though inside a collection
    # it still prints as `inspect`.
    def str(value)
      case value
      when nil then ""
      when ::String then value
      when Regexp then value.source
      when Type then value.to_s
      else write(value, true, &:to_s)
      end
    end

    # The block, if given, prints `value` itself when it isn't an rclojure
    # value (it isn't passed on to nested values).
    def write(value, readably, &foreign)
      case value
      when nil then "nil"
      when true then "true"
      when false then "false"
      when ::String then readably ? "\"#{value.gsub(/[\n\t\r\b\f"\\]/, STRING_ESCAPES)}\"" : value
      when ::Symbol then ":#{value}"
      when Rational then value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
      when Numeric, Symbol then value.to_s
      when ISeq then "(#{write_all(value, readably)})"
      when Vector then "[#{write_all(value, readably)}]"
      when Record then "##{value.class.name}{#{write_entries(value, readably)}}"
      when Map then "{#{write_entries(value, readably)}}"
      when Set then "\#{#{write_all(value, readably)}}"
      when Var, Namespace then value.to_s
      when Fn, Builtin then "#<fn #{value.name || 'anonymous'}>"
      when MultiFn then value.to_s
      when Atom then "#<Atom #{write(value.deref, readably)}>"
      when ExceptionInfo then "#<ExceptionInfo #{write(value.message, true)} #{write(value.data, true)}>"
      when Exception then "#<#{value.class} #{write(value.message, true)}>"
      when Regexp then "#\"#{value.source}\""
      when Type then "#object[#{value.class.name} 0x#{value.object_id.to_s(16)} #{write(value.to_s, true)}]"
      when Class, Module then value.name
      else foreign ? foreign.(value) : value.inspect
      end
    end

    def write_entries(map, readably)
      map.map { |k, v| "#{write(k, readably)} #{write(v, readably)}" }.join(", ")
    end

    def write_all(values, readably)
      values.map { |v| write(v, readably) }.join(" ")
    end
  end
end
