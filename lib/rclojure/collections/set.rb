module RClojure
  # A persistent set: like Clojure's PersistentHashSet, a Map from each
  # member to itself.
  class Set
    include Seqable
    include IObj
    include Enumerable

    def self.[](*items)
      new(items)
    end

    def initialize(items)
      @map = Map.new(items.to_h { |item| [item, item] })
      freeze
    end

    def self.from_map(map)
      allocate.tap { |set| set.send(:init_map, map) }
    end

    def each
      return enum_for(:each) unless block_given?

      @map.each { |item, _| yield item }
      self
    end

    def seq
      empty? ? nil : ArraySeq.new(to_a, 0)
    end

    def include?(item)
      @map.key?(item)
    end

    # Sets are functions of their members: (#{:a} :a) => :a
    def call(item)
      @map[item]
    end

    def conj(item)
      include?(item) ? self : Set.from_map(@map.assoc(item, item))
    end

    def disj(item)
      include?(item) ? Set.from_map(@map.dissoc(item)) : self
    end

    def size
      @map.size
    end

    def empty?
      @map.empty?
    end

    def ==(other)
      return true if equal?(other)

      other.is_a?(Set) && other.size == size && all? { |item| other.include?(item) }
    end
    alias eql? ==

    def hash
      [Set, sum(&:hash) & 0xFFFFFFFFFFFF].hash
    end

    def inspect
      "#<RClojure::Set #{to_a.inspect}>"
    end

    def marshal_dump
      [to_a, @meta]
    end

    def marshal_load((items, meta))
      @meta = meta
      initialize(items)
    end

    private

    def init_map(map)
      @map = map
      freeze
    end
  end
end
