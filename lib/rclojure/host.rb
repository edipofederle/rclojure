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
  end
end
