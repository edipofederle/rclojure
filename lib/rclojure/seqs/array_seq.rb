module RClojure
  # A seq over a Ruby Array from index onwards; never empty. Backs `seq`
  # on vectors, sets, maps and Ruby collections, and variadic fn args.
  class ArraySeq
    include ISeq
    include IObj

    def initialize(array, index)
      @array = array
      @index = index
      freeze
    end

    def first
      @array[@index]
    end

    def rest
      self.next || List::EMPTY
    end

    def next
      @index + 1 < @array.size ? ArraySeq.new(@array, @index + 1) : nil
    end

    def seq
      self
    end

    def size
      @array.size - @index
    end

    def counted?
      true
    end

    def to_a
      @index.zero? ? @array : @array.drop(@index)
    end

    def inspect
      "#<RClojure::ArraySeq #{to_a.inspect}>"
    end
  end
end
