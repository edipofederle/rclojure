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

  # Compiled calls with up to 3 args use these, skipping invoke's args
  # Array when the callee is an rclojure or Ruby-implemented function.
  def self.invoke0(fn)
    fn.is_a?(Fn) || fn.is_a?(Builtin) ? fn.call0 : invoke(fn, [])
  end

  def self.invoke1(fn, a)
    fn.is_a?(Fn) || fn.is_a?(Builtin) ? fn.call1(a) : invoke(fn, [a])
  end

  def self.invoke2(fn, a, b)
    fn.is_a?(Fn) || fn.is_a?(Builtin) ? fn.call2(a, b) : invoke(fn, [a, b])
  end

  def self.invoke3(fn, a, b, c)
    fn.is_a?(Fn) || fn.is_a?(Builtin) ? fn.call3(a, b, c) : invoke(fn, [a, b, c])
  end

  def self.get(coll, key, default = nil)
    case coll
    when Map then coll.key?(key) ? coll[key] : default
    when Set then coll.include?(key) ? key : default
    when Vector, ::String, Array then key.is_a?(Integer) && key.between?(0, coll.size - 1) ? coll[key] : default
    # Ruby's Hash and Set, as Clojure's get works on java.util.Map and Set.
    when Hash then coll.fetch(key, default)
    when ::Set then coll.include?(key) ? key : default
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

  # Clojure's `seq`: an ISeq over coll, or nil when it is empty. Ruby
  # Arrays and Hashes are seqable too (Hash entries become [k v] vectors),
  # as is any other Enumerable (Range, Enumerator, ...), lazily.
  def self.seq(coll)
    case coll
    when nil then nil
    when Seqable then coll.seq
    when Array then coll.empty? ? nil : ArraySeq.new(coll, 0)
    when Hash then coll.empty? ? nil : ArraySeq.new(coll.map { |key, value| Vector[key, value] }, 0)
    when Enumerable then enumerator_seq(coll.each_entry).seq
    when ::String then coll.empty? ? nil : ArraySeq.new(coll.chars.each(&:freeze), 0)
    else raise Error, "Don't know how to create ISeq from: #{coll.class.name}"
    end
  end

  # Like Clojure's iterator-seq: a lazy seq pulling items from an
  # external Enumerator, so infinite ones (`(1..)`) work too.
  def self.enumerator_seq(enumerator)
    LazySeq.new(lambda {
      begin
        item = enumerator.next
      rescue StopIteration
        return nil
      end
      Cons.new(item, enumerator_seq(enumerator))
    })
  end

  def self.first(coll)
    coll.is_a?(ISeq) ? coll.first : seq(coll)&.first
  end

  def self.rest(coll)
    return coll.rest if coll.is_a?(ISeq)

    s = seq(coll)
    s ? s.rest : List::EMPTY
  end

  def self.next(coll)
    coll.is_a?(ISeq) ? coll.next : seq(coll)&.next
  end

  def self.cons(item, coll)
    case coll
    when nil then List[item]
    when ISeq then Cons.new(item, coll)
    else Cons.new(item, seq(coll))
    end
  end

  # Yields each item of a seqable collection, walking seqs one step at a
  # time so lazy seqs are realized only as far as the block goes.
  def self.each_item(coll, &block)
    case coll
    when nil then nil
    when Vector, Set, Array then coll.each(&block)
    else
      s = seq(coll)
      while s
        yield s.first
        s = s.next
      end
    end
  end

  # All the items of a seqable collection as a Ruby Array (realizing lazy
  # seqs fully), for primitives that need them at once.
  def self.items(coll)
    case coll
    when Array then coll
    when Vector then coll.to_a
    else
      items = []
      each_item(coll) { |item| items << item }
      items
    end
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
      Interop.install(ns)
      Namespaces.install(ns, runtime)
    end

    # fast: optional fixed-arity versions of a variadic impl (see Builtin).
    def define(ns, name, impl, fast = {})
      ns.intern(name).bind_root(Builtin.new("#{ns.name}/#{name}", impl, fast))
    end
  end
end

require_relative "core/numbers"
require_relative "core/collections"
require_relative "core/text"
require_relative "core/lang"
require_relative "core/interop"
require_relative "core/namespaces"
