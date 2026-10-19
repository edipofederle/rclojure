module RClojure
  # Turns rclojure data back into readable text (Clojure's `pr-str`).
  module Printer
    STRING_ESCAPES = { "\n" => "\\n", "\t" => "\\t", "\r" => "\\r", "\b" => "\\b",
                       "\f" => "\\f", '"' => '\\"', "\\" => "\\\\" }.freeze

    module_function

    def pr_str(value)
      case value
      when nil then "nil"
      when true then "true"
      when false then "false"
      when ::String then "\"#{value.gsub(/[\n\t\r\b\f"\\]/, STRING_ESCAPES)}\""
      when ::Symbol then ":#{value}"
      when Rational then value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
      when Numeric, Symbol then value.to_s
      when List then "(#{value.map { |v| pr_str(v) }.join(' ')})"
      when Vector then "[#{value.map { |v| pr_str(v) }.join(' ')}]"
      when Map then "{#{value.map { |k, v| "#{pr_str(k)} #{pr_str(v)}" }.join(', ')}}"
      when Set then "\#{#{value.map { |v| pr_str(v) }.join(' ')}}"
      when Var then value.to_s
      when Fn, Builtin then "#<fn #{value.name || 'anonymous'}>"
      when ExceptionInfo then "#<ExceptionInfo #{pr_str(value.message)} #{pr_str(value.data)}>"
      when Exception then "#<#{value.class} #{pr_str(value.message)}>"
      else value.inspect
      end
    end
  end
end
