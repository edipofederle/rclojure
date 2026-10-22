module RClojure
  # A persistent map. Like Clojure, small maps (up to ARRAY_MAP_MAX
  # entries) are copied on write and keep insertion order, as
  # PersistentArrayMap does; here they are frozen Ruby Hashes. Past that
  # a map becomes a hash array mapped trie (HashTrie), as
  # PersistentHashMap, sharing structure between versions, and stays one.
  class Map
    include Seqable
    include IObj
    include Enumerable

    ARRAY_MAP_MAX = 8
    NOT_FOUND = Object.new.freeze
    private_constant :NOT_FOUND

    def self.[](hash = {})
      new(hash)
    end

    def initialize(hash)
      if hash.size <= ARRAY_MAP_MAX
        @hash = hash.dup.freeze
        @size = hash.size
      else
        @root, @size = Map.trie_from(hash)
      end
      freeze
    end

    def self.trie_from(pairs)
      added = [false]
      size = 0
      root = pairs.reduce(HashTrie::BitmapNode::EMPTY) do |node, (key, value)|
        added[0] = false
        node = node.assoc(0, HashTrie.hash_of(key), key, value, added)
        size += 1 if added[0]
        node
      end
      [root, size]
    end

    def self.from_trie(root, size)
      allocate.tap { |map| map.send(:init_trie, root, size) }
    end

    def each(&block)
      return enum_for(:each) unless block

      @hash ? @hash.each { |key, value| yield(key, value) } : @root.each(&block)
      self
    end

    # Entries are [key value] vectors.
    def seq
      empty? ? nil : ArraySeq.new(map { |key, value| Vector[key, value] }, 0)
    end

    def [](key)
      call(key)
    end

    def key?(key)
      !lookup(key).equal?(NOT_FOUND)
    end

    # Maps are functions of their keys: ({:a 1} :a) => 1
    def call(key, default = nil)
      value = lookup(key)
      value.equal?(NOT_FOUND) ? default : value
    end

    def assoc(key, value)
      # Map.new makes a trie once the map grows past ARRAY_MAP_MAX.
      return Map.new(@hash.merge(key => value)) if @hash

      added = [false]
      root = @root.assoc(0, HashTrie.hash_of(key), key, value, added)
      root.equal?(@root) ? self : Map.from_trie(root, added[0] ? @size + 1 : @size)
    end

    def dissoc(key)
      return self unless key?(key)

      if @hash
        hash = @hash.dup
        hash.delete(key)
        return Map.new(hash)
      end

      Map.from_trie(@root.without(0, HashTrie.hash_of(key), key) || HashTrie::BitmapNode::EMPTY, @size - 1)
    end

    def keys
      map { |key, _| key }
    end

    def values
      map { |_, value| value }
    end

    attr_reader :size

    def empty?
      @size.zero?
    end

    def to_h
      @hash || each_with_object({}) { |(key, value), hash| hash[key] = value }
    end

    def ==(other)
      return true if equal?(other)

      other.is_a?(Map) && other.size == size &&
        all? { |key, value| other.key?(key) && RClojure.equiv?(value, other[key]) }
    end
    alias eql? ==

    # Independent of entry order and representation, as equal maps may
    # differ in both.
    def hash
      [Map, sum { |key, value| [key, value].hash } & 0xFFFFFFFFFFFF].hash
    end

    def inspect
      "#<RClojure::Map #{to_h.inspect}>"
    end

    def marshal_dump
      [to_h, @meta]
    end

    def marshal_load((hash, meta))
      @meta = meta
      initialize(hash)
    end

    private

    def init_trie(root, size)
      @root = root
      @size = size
      freeze
    end

    def lookup(key)
      @hash ? @hash.fetch(key, NOT_FOUND) : @root.find(0, HashTrie.hash_of(key), key, NOT_FOUND)
    end
  end
end
