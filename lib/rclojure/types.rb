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
      other.is_a?(Sequential) && other.to_a == to_a
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

    def assoc(key, value)
      Map.new(@hash.merge(key => value))
    end

    def size
      @hash.size
    end

    def to_h
      @hash
    end

    def ==(other)
      other.is_a?(Map) && other.to_h == to_h
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

    def size
      @items.size
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
