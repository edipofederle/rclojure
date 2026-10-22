module RClojure
  # `seq` on a vector, walking its leaf Arrays in turn, like Clojure's
  # chunked seq over a PersistentVector: next is O(1) within a leaf.
  # Never empty.
  class VectorSeq
    include ISeq
    include IObj

    # node is the leaf holding the vector's items from index on; offset
    # is the position within it.
    def initialize(vector, node, index, offset)
      @vector = vector
      @node = node
      @index = index
      @offset = offset
      freeze
    end

    def first
      @node[@offset]
    end

    def rest
      self.next || List::EMPTY
    end

    def next
      return VectorSeq.new(@vector, @node, @index, @offset + 1) if @offset + 1 < @node.size

      start = @index + @node.size
      VectorSeq.new(@vector, @vector.array_for(start), start, 0) if start < @vector.size
    end

    def seq
      self
    end

    def size
      @vector.size - @index - @offset
    end

    def counted?
      true
    end

    def inspect
      "#<RClojure::VectorSeq #{to_a.inspect}>"
    end
  end
end
