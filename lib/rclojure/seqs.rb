module RClojure
  # A seq of first followed by more (an ISeq or nil), as built by `cons`.
  class Cons
    include ISeq

    def initialize(first, more)
      @first = first
      @more = more
      freeze
    end

    def first
      @first
    end

    def rest
      @more || List::EMPTY
    end

    def next
      RClojure.seq(@more)
    end

    def seq
      self
    end

    def inspect
      "#<RClojure::Cons #{@first.inspect} #{@more.inspect}>"
    end
  end

  # A seq over a Ruby Array from index onwards; never empty. Backs `seq`
  # on vectors, sets, maps and Ruby collections, and variadic fn args.
  class ArraySeq
    include ISeq

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

  # Created by the `lazy-seq` macro: fn is called, once, the first time
  # the seq is needed. Like Clojure's LazySeq, the result may be any
  # seqable value (including another LazySeq) and is cached.
  class LazySeq
    include ISeq

    def initialize(fn)
      @fn = fn
      @value = nil
      @seq = nil
    end

    def realized?
      @fn.nil?
    end

    def seq
      realize
      unless @value.nil?
        value = @value
        @value = nil
        # Unwrap nested lazy seqs iteratively so long chains of them
        # (e.g. filter skipping many items) don't grow the Ruby stack.
        value = value.realize while value.is_a?(LazySeq)
        @seq = RClojure.seq(value)
      end
      @seq
    end

    def first
      seq&.first
    end

    def rest
      seq ? @seq.rest : List::EMPTY
    end

    def next
      seq&.next
    end

    def inspect
      realized? ? "#<RClojure::LazySeq #{to_a.inspect}>" : "#<RClojure::LazySeq (unrealized)>"
    end

    protected

    # Calls fn if it hasn't been called; returns the value still to be
    # turned into a seq, or the seq itself once that has happened.
    def realize
      if @fn
        @value = @fn.call
        @fn = nil
      end
      @value.nil? ? @seq : @value
    end
  end
end
