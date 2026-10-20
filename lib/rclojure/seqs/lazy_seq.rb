module RClojure
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
