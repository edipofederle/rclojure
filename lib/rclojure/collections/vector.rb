module RClojure
  # A persistent vector, ported from Clojure's PersistentVector: a 32-way
  # trie of frozen Arrays plus a tail Array holding the last (up to 32)
  # items, so conj, pop, nth and assoc copy at most one path of nodes.
  # Nodes hold only the children present (Clojure's are 32 slots wide
  # with nils), so Clojure's "set slot to null" becomes dropping the last.
  class Vector
    include Seqable
    include IObj
    include Sequential

    BITS = 5
    WIDTH = 1 << BITS
    MASK = WIDTH - 1
    EMPTY_NODE = [].freeze

    def self.[](*items)
      new(items)
    end

    # Builds the trie a run of conjs would, a level at a time.
    def initialize(items)
      # Up to WIDTH items fit in the tail alone (the common case).
      return init(items.size, BITS, EMPTY_NODE, items.dup.freeze) if items.size <= WIDTH

      tail_offset = Vector.tail_offset(items.size)
      nodes = items[0, tail_offset].each_slice(WIDTH).map(&:freeze)
      shift = BITS
      while nodes.size > WIDTH
        nodes = nodes.each_slice(WIDTH).map(&:freeze)
        shift += BITS
      end
      init(items.size, shift, nodes.freeze, items[tail_offset..].freeze)
    end

    def self.build(count, shift, root, tail)
      allocate.tap { |vector| vector.send(:init, count, shift, root, tail) }
    end

    # Index of the first item in the tail.
    def self.tail_offset(count)
      count < WIDTH ? 0 : ((count - 1) >> BITS) << BITS
    end

    attr_reader :size

    def seq
      empty? ? nil : VectorSeq.new(self, array_for(0), 0, 0)
    end

    def each(&block)
      return enum_for(:each) unless block

      (0...tail_offset).step(WIDTH) { |i| array_for(i).each(&block) }
      @tail.each(&block)
      self
    end

    def to_a
      items = []
      each { |item| items << item }
      items
    end

    def empty?
      @size.zero?
    end

    def counted?
      true
    end

    def ==(other)
      return super unless other.is_a?(Vector)

      equal?(other) ||
        (size == other.size && each_with_index.all? { |item, i| RClojure.equiv?(item, other[i]) })
    end
    alias eql? ==

    # The item at index, or nil when it's out of bounds.
    def [](index)
      return nil unless index.is_a?(Integer) && index.between?(0, @size - 1)

      array_for(index)[index & MASK]
    end

    # The leaf Array holding index (the tail, or a trie leaf).
    def array_for(index)
      return @tail if index >= tail_offset

      node = @root
      level = @shift
      while level.positive?
        node = node[(index >> level) & MASK]
        level -= BITS
      end
      node
    end

    def conj(item)
      if @size - tail_offset < WIDTH
        return Vector.build(@size + 1, @shift, @root, (@tail + [item]).freeze)
      end

      # The tail is full: push it into the trie, adding a level if the root is full.
      shift = @shift
      if (@size >> BITS) > (1 << @shift)
        root = [@root, new_path(@shift, @tail)].freeze
        shift += BITS
      else
        root = push_tail(@shift, @root, @tail)
      end
      Vector.build(@size + 1, shift, root, [item].freeze)
    end

    # Replaces the item at index, or appends when index == size.
    def assoc(index, value)
      unless index.is_a?(Integer) && index.between?(0, @size)
        raise IndexError, "Index #{index} out of bounds for vector of size #{@size}"
      end
      return conj(value) if index == @size

      if index >= tail_offset
        tail = @tail.dup
        tail[index & MASK] = value
        return Vector.build(@size, @shift, @root, tail.freeze)
      end
      Vector.build(@size, @shift, do_assoc(@shift, @root, index, value), @tail)
    end

    def peek
      empty? ? nil : self[@size - 1]
    end

    def pop
      raise Error, "Can't pop empty vector" if empty?
      return Vector[] if @size == 1
      return Vector.build(@size - 1, @shift, @root, @tail[0...-1].freeze) if @size - tail_offset > 1

      tail = array_for(@size - 2)
      root = pop_tail(@shift, @root) || EMPTY_NODE
      shift = @shift
      if shift > BITS && root.size == 1
        root = root.first
        shift -= BITS
      end
      Vector.build(@size - 1, shift, root, tail)
    end

    # Vectors are functions of their indices: ([:a :b] 1) => :b
    def call(index)
      unless index.is_a?(Integer) && index.between?(0, @size - 1)
        raise IndexError, "Index #{index} out of bounds for vector of size #{@size}"
      end

      self[index]
    end

    def inspect
      "#<RClojure::Vector #{to_a.inspect}>"
    end

    def marshal_dump
      [to_a, @meta]
    end

    def marshal_load((items, meta))
      @meta = meta
      initialize(items)
    end

    private

    def init(size, shift, root, tail)
      @size = size
      @shift = shift
      @root = root
      @tail = tail
      freeze
    end

    def tail_offset
      Vector.tail_offset(@size)
    end

    def push_tail(level, parent, tail_node)
      index = ((@size - 1) >> level) & MASK
      node = parent.dup
      node[index] =
        if level == BITS
          tail_node
        elsif (child = parent[index])
          push_tail(level - BITS, child, tail_node)
        else
          new_path(level - BITS, tail_node)
        end
      node.freeze
    end

    def new_path(level, node)
      level.zero? ? node : [new_path(level - BITS, node)].freeze
    end

    def do_assoc(level, node, index, value)
      copy = node.dup
      if level.zero?
        copy[index & MASK] = value
      else
        child_index = (index >> level) & MASK
        copy[child_index] = do_assoc(level - BITS, node[child_index], index, value)
      end
      copy.freeze
    end

    # The node without the last leaf, or nil if that leaves it empty.
    def pop_tail(level, node)
      index = ((@size - 2) >> level) & MASK
      if level > BITS
        child = pop_tail(level - BITS, node[index])
        return nil if child.nil? && index.zero?

        copy = node.dup
        child ? copy[index] = child : copy.pop
        copy.freeze
      elsif index.zero?
        nil
      else
        node[0...index].freeze
      end
    end
  end
end
