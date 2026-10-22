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
        # Characters are one-character strings, as in ClojureScript.
        define.("char?", ->(x) { x.is_a?(::String) && x.length == 1 })
        define.("char", lambda { |x|
          case x
          when Integer then x.chr(Encoding::UTF_8).freeze
          when ::String then x.length == 1 ? x : raise(ArgumentError, "Argument to char must be a character or number")
          else raise ArgumentError, "Argument to char must be a character or number"
          end
        })
        define.("keyword?", ->(x) { x.is_a?(::Symbol) })
        define.("symbol?", ->(x) { x.is_a?(Symbol) })

        define.("re-pattern", ->(x) { x.is_a?(Regexp) ? x : Regexp.new(x).freeze })
        define.("re-find", ->(re, s) { (match = re.match(s)) && re_groups(match) })
        define.("re-matches", lambda { |re, s|
          (match = Regexp.new("\\A(?:#{re.source})\\z", re.options).match(s)) && re_groups(match)
        })
        define.("re-seq", ->(re, s) { re_seq(re, s, 0).seq })

        define.("pr-str", ->(*values) { values.map { |v| Printer.pr_str(v) }.join(" ") })
        define.("print-str", ->(*values) { values.map { |v| Printer.print_str(v) }.join(" ") })
        define.("pr", ->(*values) { output(values.map { |v| Printer.pr_str(v) }.join(" ")) })
        define.("prn", ->(*values) { output(values.map { |v| Printer.pr_str(v) }.join(" ") + "\n") })
        define.("print", ->(*values) { output(values.map { |v| Printer.print_str(v) }.join(" ")) })
        define.("println", ->(*values) { output(values.map { |v| Printer.print_str(v) }.join(" ") + "\n") })
        define.("newline", -> { output("\n") })
      end

      # Like Clojure's re-groups: the match, or with capture groups a vector
      # of it followed by each group (nil when a group didn't take part).
      def re_groups(match)
        match.size == 1 ? match[0] : Vector.new(match.to_a)
      end

      # Every match of re in s from pos, lazily. Like Matcher.find, an empty
      # match moves the next search on by a character.
      def re_seq(re, s, pos)
        LazySeq.new(lambda {
          match = re.match(s, pos) or return nil
          following = match.end(0) == match.begin(0) ? match.end(0) + 1 : match.end(0)
          Cons.new(re_groups(match), following > s.length ? nil : re_seq(re, s, following))
        })
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
