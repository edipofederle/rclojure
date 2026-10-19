module RClojure
  # Calls anything callable. Keywords look themselves up: `(:a m)`.
  def self.invoke(fn, args)
    case fn
    when ::Symbol
      unless args.size.between?(1, 2)
        raise ArityError, "Wrong number of args (#{args.size}) passed to: #{Printer.pr_str(fn)}"
      end

      get(args[0], fn, args[1])
    else
      raise Error, "#{Printer.pr_str(fn)} is not a function" unless fn.respond_to?(:call)

      fn.call(*args)
    end
  end

  def self.get(coll, key, default = nil)
    case coll
    when Map then coll.key?(key) ? coll[key] : default
    when Set then coll.include?(key) ? key : default
    when Vector then key.is_a?(Integer) && key.between?(0, coll.size - 1) ? coll[key] : default
    else default
    end
  end

  # Clojure's `=`: like Ruby's ==, except integers/ratios never equal
  # floats. Collections apply the same rule to their elements.
  def self.equiv?(a, b)
    if a.is_a?(Numeric) && b.is_a?(Numeric)
      a.is_a?(Float) == b.is_a?(Float) && a == b
    else
      a == b
    end
  end

  # The items of a collection as a Ruby Array; map entries become [k v]
  # vectors. This stands in for the seq abstraction until lazy seqs land.
  def self.items(coll)
    case coll
    when nil then []
    when Sequential, Set then coll.to_a
    when Map then coll.map { |key, value| Vector[key, value] }
    else raise Error, "Don't know how to create ISeq from: #{coll.class.name}"
    end
  end

  # Clojure's `seq`: nil for an empty collection, otherwise a list.
  def self.seq(coll)
    return coll if coll.is_a?(List) && !coll.empty?

    items = items(coll)
    items.empty? ? nil : List.new(items)
  end

  def self.truthy?(value)
    !(value.nil? || value.equal?(false))
  end

  # Primitive functions implemented in Ruby. The rest of clojure.core will
  # be written in rclojure itself once macros exist.
  module Core
    module_function

    def install(ns, runtime)
      Numbers.install(ns)
      Collections.install(ns)
      Text.install(ns)
      Lang.install(ns, runtime)
    end

    def define(ns, name, impl)
      ns.intern(name).bind_root(Builtin.new("#{ns.name}/#{name}", impl))
    end
  end
end

require_relative "core/numbers"
require_relative "core/collections"
require_relative "core/text"
require_relative "core/lang"
