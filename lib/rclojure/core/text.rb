module RClojure
  module Core
    # Strings, symbols, keywords and printing.
    module Text
      module_function

      def install(ns)
        define = ->(name, impl) { Core.define(ns, name, impl) }

        define.("str", ->(*values) { values.map { |v| Printer.str(v) }.join })
        define.("subs", lambda { |string, start, finish = string.length|
          unless start.between?(0, string.length) && finish.between?(start, string.length)
            raise IndexError, "String index out of range: begin #{start}, end #{finish}, length #{string.length}"
          end

          string[start...finish]
        })

        define.("name", ->(x) { name_parts(x).last })
        define.("namespace", ->(x) { name_parts(x).first })
        define.("keyword", lambda { |ns_or_name, name = nil|
          return (ns_or_name ? "#{ns_or_name}/#{name}" : name).to_sym if name
          return ns_or_name if ns_or_name.is_a?(::Symbol)

          ns_or_name.to_s.to_sym
        })
        define.("symbol", lambda { |ns_or_name, name = nil|
          return Symbol.new(ns_or_name, name) if name
          return ns_or_name if ns_or_name.is_a?(Symbol)

          Symbol.parse(ns_or_name.is_a?(::Symbol) ? ns_or_name.to_s : ns_or_name)
        })

        define.("string?", ->(x) { x.is_a?(::String) })
        define.("keyword?", ->(x) { x.is_a?(::Symbol) })
        define.("symbol?", ->(x) { x.is_a?(Symbol) })

        define.("pr-str", ->(*values) { values.map { |v| Printer.pr_str(v) }.join(" ") })
        define.("print-str", ->(*values) { values.map { |v| Printer.print_str(v) }.join(" ") })
        define.("pr", ->(*values) { output(values.map { |v| Printer.pr_str(v) }.join(" ")) })
        define.("prn", ->(*values) { output(values.map { |v| Printer.pr_str(v) }.join(" ") + "\n") })
        define.("print", ->(*values) { output(values.map { |v| Printer.print_str(v) }.join(" ")) })
        define.("println", ->(*values) { output(values.map { |v| Printer.print_str(v) }.join(" ") + "\n") })
        define.("newline", -> { output("\n") })
      end

      # [namespace, name] of a string, symbol or keyword.
      def name_parts(x)
        case x
        when ::String then [nil, x]
        when Symbol then [x.ns, x.name]
        when ::Symbol
          symbol = Symbol.parse(x.to_s)
          [symbol.ns, symbol.name]
        else raise ArgumentError, "Doesn't support name: #{Printer.pr_str(x)}"
        end
      end

      def output(text)
        $stdout.write(text)
        nil
      end
    end
  end
end
