module RClojure
  # Values that carry metadata, like Clojure's IObj: with_meta returns a
  # copy with other metadata. Equality and hashing ignore it.
  module IObj
    def meta
      @meta
    end

    def with_meta(meta)
      return self if meta.equal?(@meta)

      copy = dup
      copy.instance_variable_set(:@meta, meta)
      copy.freeze
    end
  end

  # A Clojure symbol, optionally namespace-qualified: `foo`, `clojure.core/map`.
  # Keywords are not represented here; they map to plain Ruby Symbols.
  class Symbol
    include IObj
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
      [@ns, @name, @meta]
    end

    def marshal_load((ns, name, meta))
      @meta = meta
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

  # A counted singly-linked list, like Clojure's PersistentList.
  class List
    include ISeq
    include IObj

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
      [to_a, @meta]
    end

    def marshal_load((items, meta))
      @meta = meta
      initialize(items.first, List.from(items.drop(1)), items.size)
    end
  end
  List::EMPTY = List.new(nil, nil, 0)
end
