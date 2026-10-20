module RClojure
  # Access to the host (Ruby) platform: constants and method calls.
  module Host
    NOT_FOUND = Object.new.freeze

    module_function

    # The Ruby constant named by `name` ("Math", "File::Stat"), or NOT_FOUND.
    # Only capitalized names are considered, so ordinary symbols never
    # resolve to Ruby constants by accident.
    def constant(name)
      return NOT_FOUND unless name.match?(/\A[A-Z]/)

      Object.const_get(name)
    rescue NameError
      NOT_FOUND
    end

    def module?(name)
      constant(name).is_a?(Module)
    end

    # Ruby method names can't contain '-', so (.each-slice x) calls each_slice.
    def method_name(name)
      name.tr("-", "_").to_sym
    end

    # The block for `(.method x & f)`. Like Ruby's `&f`, anything with
    # to_proc is converted with it (so `& :upcase` calls upcase, as in
    # Ruby); other rclojure callables (maps, sets, vectors) are invoked.
    def block(f)
      return nil if f.nil?
      return f.to_proc if f.respond_to?(:to_proc)

      proc { |*args| RClojure.invoke(f, args) }
    end

    # Clojure's clj->js for Ruby: maps become Hashes and other collections
    # (including seqs, realized) Arrays, recursively; symbols become
    # strings. Keywords are already Ruby Symbols.
    def to_ruby(value)
      case value
      when Symbol then value.to_s
      when Map then value.each_with_object({}) { |(key, item), hash| hash[to_ruby(key)] = to_ruby(item) }
      when Sequential, Set then value.map { |item| to_ruby(item) }
      else value
      end
    end

    # Clojure's js->clj for Ruby: Arrays become vectors and Hashes maps,
    # recursively, including inside rclojure collections.
    def from_ruby(value)
      case value
      when Array, Vector then Vector.new(value.map { |item| from_ruby(item) })
      when Hash, Map then Map.new(value.each_with_object({}) { |(key, item), hash| hash[from_ruby(key)] = from_ruby(item) })
      when Set, ::Set then Set.new(value.map { |item| from_ruby(item) })
      when ISeq then List.from(value.map { |item| from_ruby(item) })
      else value
      end
    end
  end
end
