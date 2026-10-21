module RClojure
  # A Clojure symbol, optionally namespace-qualified: `foo`, `clojure.core/map`.
  # Keywords are not represented here; they map to plain Ruby Symbols.
  class Symbol
    attr_reader :ns, :name

    def self.parse(text)
      return new(nil, text) if text == "/" || !text.include?("/")

      ns, name = text.split("/", 2)
      new(ns, name)
    end

    def initialize(ns, name)
      @ns = ns&.freeze
      @name = name.freeze
      freeze
    end

    def to_s
      ns ? "#{ns}/#{name}" : name
    end

    def ==(other)
      other.is_a?(Symbol) && other.ns == ns && other.name == name
    end
    alias eql? ==

    def hash
      [Symbol, ns, name].hash
    end

    def inspect
      "#<RClojure::Symbol #{self}>"
    end

    # Marshal support (for the core cache) restores frozen values.
    def marshal_dump
      [@ns, @name]
    end

    def marshal_load((ns, name))
      initialize(ns, name)
    end
  end

  # Anything `seq` works on. Including classes define #seq, returning an
  # ISeq or nil when empty.
  module Seqable; end

  # Marker for ordered collections; Clojure considers `(1 2)` and `[1 2]` equal.
  module Sequential
    include Enumerable

    # Like Clojure's ASeq.equiv: walks both seqs, comparing items with `=`.
    def ==(other)
      return true if equal?(other)
      return false unless other.is_a?(Sequential)
      return false if counted? && other.counted? && size != other.size

      xs = seq
      ys = other.seq
      while xs
        return false if ys.nil? || !RClojure.equiv?(xs.first, ys.first)

        xs = xs.next
        ys = ys.next
      end
      ys.nil?
    end
    alias eql? ==

    def hash
      [Sequential, to_a].hash
    end

    # Whether size is known without walking the collection.
    def counted?
      false
    end
  end

  # A sequence: first, rest (never nil) and next (nil when exhausted).
  # Includers define #first, #rest, #next and #seq.
  module ISeq
    include Seqable
    include Sequential

    def each
      return enum_for(:each) unless block_given?

      s = seq
      while s
        yield s.first
        s = s.next
      end
      self
    end

    def size
      count
    end

    def empty?
      seq.nil?
    end
  end

  # NOTE: Vector, Map and Set below are immutable wrappers over frozen Ruby
  # collections. They will be replaced with structurally-shared persistent
  # data structures (HAMT, 32-way trie vector) in a later milestone.

  # A counted singly-linked list, like Clojure's PersistentList.
  class List
    include ISeq

    attr_reader :size

    def self.[](*items)
      from(items)
    end

    def self.from(items)
      list = EMPTY
      items.reverse_each { |item| list = list.cons(item) }
      list
    end

    def initialize(first, rest, size)
      @first = first
      @rest = rest
      @size = size
      freeze
    end

    def first
      @first
    end

    def rest
      @size > 1 ? @rest : EMPTY
    end

    def next
      @size > 1 ? @rest : nil
    end

    def seq
      @size.zero? ? nil : self
    end

    def empty?
      @size.zero?
    end

    def counted?
      true
    end

    def each
      return enum_for(:each) unless block_given?

      list = self
      until list.empty?
        yield list.first
        list = list.rest
      end
      self
    end

    def to_a
      items = []
      each { |item| items << item }
      items
    end

    def cons(item)
      List.new(item, self, @size + 1)
    end
    alias conj cons

    def peek
      @first
    end

    def pop
      raise Error, "Can't pop empty list" if empty?

      rest
    end

    def inspect
      "#<RClojure::List #{to_a.inspect}>"
    end

    def marshal_dump
      to_a
    end

    def marshal_load(items)
      initialize(items.first, List.from(items.drop(1)), items.size)
    end
  end
  List::EMPTY = List.new(nil, nil, 0)

  class Vector
    include Seqable
    include Sequential

    def self.[](*items)
      new(items)
    end

    def initialize(items)
      @items = items.dup.freeze
      freeze
    end

    def seq
      @items.empty? ? nil : ArraySeq.new(@items, 0)
    end

    def each(&block)
      @items.each(&block)
    end

    def to_a
      @items
    end

    def size
      @items.size
    end

    def empty?
      @items.empty?
    end

    def counted?
      true
    end

    def ==(other)
      other.is_a?(Vector) ? size == other.size && @items.zip(other.to_a).all? { |x, y| RClojure.equiv?(x, y) } : super
    end
    alias eql? ==

    def [](index)
      @items[index]
    end

    def conj(item)
      Vector.new([*@items, item])
    end

    # Replaces the item at index, or appends when index == size.
    def assoc(index, value)
      unless index.is_a?(Integer) && index.between?(0, size)
        raise IndexError, "Index #{index} out of bounds for vector of size #{size}"
      end

      items = @items.dup
      items[index] = value
      Vector.new(items)
    end

    def peek
      @items.last
    end

    def pop
      raise Error, "Can't pop empty vector" if empty?

      Vector.new(@items[0...-1])
    end

    # Vectors are functions of their indices: ([:a :b] 1) => :b
    def call(index)
      unless index.is_a?(Integer) && index.between?(0, size - 1)
        raise IndexError, "Index #{index} out of bounds for vector of size #{size}"
      end

      @items[index]
    end

    def inspect
      "#<RClojure::Vector #{@items.inspect}>"
    end

    def marshal_dump
      @items
    end

    def marshal_load(items)
      initialize(items)
    end
  end

  class Map
    include Seqable
    include Enumerable

    def self.[](hash = {})
      new(hash)
    end

    def initialize(hash)
      @hash = hash.dup.freeze
      freeze
    end

    def each(&block)
      @hash.each(&block)
    end

    # Entries are [key value] vectors.
    def seq
      @hash.empty? ? nil : ArraySeq.new(@hash.map { |key, value| Vector[key, value] }, 0)
    end

    def [](key)
      @hash[key]
    end

    def key?(key)
      @hash.key?(key)
    end

    # Maps are functions of their keys: ({:a 1} :a) => 1
    def call(key, default = nil)
      @hash.fetch(key, default)
    end

    def assoc(key, value)
      Map.new(@hash.merge(key => value))
    end

    def dissoc(key)
      return self unless @hash.key?(key)

      hash = @hash.dup
      hash.delete(key)
      Map.new(hash)
    end

    def keys
      @hash.keys
    end

    def values
      @hash.values
    end

    def size
      @hash.size
    end

    def empty?
      @hash.empty?
    end

    def to_h
      @hash
    end

    def ==(other)
      other.is_a?(Map) && other.size == size &&
        @hash.all? { |key, value| other.key?(key) && RClojure.equiv?(value, other[key]) }
    end
    alias eql? ==

    def hash
      [Map, @hash].hash
    end

    def inspect
      "#<RClojure::Map #{@hash.inspect}>"
    end

    def marshal_dump
      @hash
    end

    def marshal_load(hash)
      initialize(hash)
    end
  end

  class Set
    include Seqable
    include Enumerable

    def self.[](*items)
      new(items)
    end

    def initialize(items)
      @items = items.each_with_object({}) { |item, acc| acc[item] = true }.freeze
      freeze
    end

    def each(&block)
      @items.each_key(&block)
    end

    def seq
      @items.empty? ? nil : ArraySeq.new(@items.keys, 0)
    end

    def include?(item)
      @items.key?(item)
    end

    # Sets are functions of their members: (#{:a} :a) => :a
    def call(item)
      include?(item) ? item : nil
    end

    def conj(item)
      include?(item) ? self : Set.new([*@items.keys, item])
    end

    def disj(item)
      include?(item) ? Set.new(@items.keys - [item]) : self
    end

    def size
      @items.size
    end

    def empty?
      @items.empty?
    end

    def ==(other)
      other.is_a?(Set) && other.size == size && all? { |item| other.include?(item) }
    end
    alias eql? ==

    def hash
      [Set, @items.keys.map(&:hash).sort].hash
    end

    def inspect
      "#<RClojure::Set #{@items.keys.inspect}>"
    end

    def marshal_dump
      @items.keys
    end

    def marshal_load(items)
      initialize(items)
    end
  end
end
