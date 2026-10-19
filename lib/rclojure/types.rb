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
  end

  # Marker for ordered collections; Clojure considers `(1 2)` and `[1 2]` equal.
  module Sequential
    include Enumerable

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

    def ==(other)
      return false unless other.is_a?(Sequential) && other.size == size

      other.to_a.each_with_index.all? { |item, i| RClojure.equiv?(@items[i], item) }
    end
    alias eql? ==

    def hash
      [Sequential, @items].hash
    end
  end

  # NOTE: the collections below are immutable wrappers over frozen Ruby
  # collections. They will be replaced with structurally-shared persistent
  # data structures (HAMT, 32-way trie vector) in a later milestone.

  class List
    include Sequential

    def self.[](*items)
      new(items)
    end

    def initialize(items)
      @items = items.dup.freeze
      freeze
    end

    def first
      @items.first
    end

    def rest
      List[*@items.drop(1)]
    end

    def cons(item)
      List.new([item, *@items])
    end
    alias conj cons

    def peek
      @items.first
    end

    def pop
      raise Error, "Can't pop empty list" if empty?

      rest
    end

    def inspect
      "#<RClojure::List #{@items.inspect}>"
    end
  end
  List::EMPTY = List.new([])

  class Vector
    include Sequential

    def self.[](*items)
      new(items)
    end

    def initialize(items)
      @items = items.dup.freeze
      freeze
    end

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
  end

  class Map
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
  end

  class Set
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
  end
end
