module RClojure
  module Core
    # Working with Ruby objects and classes.
    module Interop
      module_function

      def install(ns)
        define = ->(name, impl) { Core.define(ns, name, impl) }

        define.("instance?", ->(klass, x) { x.is_a?(klass) })
        define.("class", ->(x) { x&.class })
        define.("clj->rb", ->(x) { Host.to_ruby(x) })
        define.("rb->clj", ->(x) { Host.from_ruby(x) })
      end
    end
  end
end
