module RClojure
  module Core
    # Working with Ruby objects and classes.
    module Interop
      module_function

      # A class's superclass and the modules it includes or prepends
      # directly (for a module, the modules it includes).
      def bases(c)
        return c.ancestors - [c] unless c.is_a?(Class) && c.superclass

        c.ancestors.take_while { |m| !m.equal?(c.superclass) } - [c] + [c.superclass]
      end

      def install(ns)
        define = ->(name, impl) { Core.define(ns, name, impl) }

        define.("instance?", ->(klass, x) { x.is_a?(klass) })
        define.("class", ->(x) { x&.class })
        # Ruby classes and modules play the part of Java classes and interfaces.
        define.("class?", ->(x) { x.is_a?(Module) })
        define.("bases", ->(c) { RClojure.seq(bases(c)) })
        define.("supers", lambda { |c|
          supers = c.ancestors - [c]
          supers.empty? ? nil : Set.new(supers)
        })
        define.("clj->rb", ->(x) { Host.to_ruby(x) })
        define.("rb->clj", ->(x) { Host.from_ruby(x) })
      end
    end
  end
end
