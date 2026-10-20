module RClojure
  # Expands `form into code that builds form, the way Clojure's reader does:
  #   `(a ~b ~@c)  =>  (clojure.core/seq (clojure.core/concat
  #                       (clojure.core/list (quote user/a))
  #                       (clojure.core/list b)
  #                       c))
  # Symbols are namespace-qualified (special forms excepted), and `x#`
  # becomes a generated symbol, consistent within one syntax-quote.
  class SyntaxQuote
    # Clojure's Compiler.specials: never qualified.
    UNQUALIFIED = (Analyzer::SPECIAL_FORMS + %w[& catch finally . new set!]).freeze
    QUOTE = Symbol.new(nil, "quote")
    UNQUOTE = Symbol.new(nil, "unquote")
    UNQUOTE_SPLICING = Symbol.new(nil, "unquote-splicing")

    def initialize(runtime)
      @runtime = runtime
      @gensyms = {}
    end

    def expand(form)
      case form
      when Symbol then List[QUOTE, qualify(form)]
      when ISeq then expand_list(form)
      when Vector then apply_to("vector", form)
      when Set then apply_to("hash-set", form)
      when Map then apply_to("hash-map", form.flat_map { |key, value| [key, value] })
      else form # nil, booleans, numbers, strings, keywords evaluate to themselves
      end
    end

    private

    def expand_list(form)
      return List[core("list")] if form.empty?

      case form.first
      when UNQUOTE then form.to_a[1]
      when UNQUOTE_SPLICING then raise CompilerError, "Unquote-splicing (~@) used outside of a list"
      # A nested syntax-quote expands inside-out, like Clojure's reader.
      when Analyzer::SYNTAX_QUOTE then expand(expand(form.to_a[1]))
      else List[core("seq"), List[core("concat"), *parts(form)]]
      end
    end

    def apply_to(constructor, items)
      List[core("apply"), core(constructor), List[core("seq"), List[core("concat"), *parts(items)]]]
    end

    def parts(items)
      items.map do |item|
        if form_of?(item, UNQUOTE)
          List[core("list"), item.to_a[1]]
        elsif form_of?(item, UNQUOTE_SPLICING)
          item.to_a[1]
        else
          List[core("list"), expand(item)]
        end
      end
    end

    def form_of?(item, head)
      item.is_a?(ISeq) && item.first == head
    end

    def qualify(symbol)
      return symbol if symbol.ns
      return symbol if UNQUALIFIED.include?(symbol.name)
      # Ruby interop forms (.method, Class.) are left alone.
      return symbol if symbol.name.start_with?(".") || symbol.name.end_with?(".")
      return auto_gensym(symbol) if symbol.name.end_with?("#")

      var = @runtime.current_ns.find_var(symbol.name)
      return Symbol.new(var.ns.name, symbol.name) if var
      return symbol unless Host.constant(symbol.name).equal?(Host::NOT_FOUND) # Ruby class names stay as-is

      Symbol.new(@runtime.current_ns.name, symbol.name)
    end

    def auto_gensym(symbol)
      @gensyms[symbol.name] ||= Symbol.new(nil, "#{symbol.name.chomp('#')}__#{@runtime.next_id}__auto__")
    end

    def core(name)
      Symbol.new("clojure.core", name)
    end
  end
end
