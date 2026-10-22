module RClojure
  # A seq of first followed by more (an ISeq or nil), as built by `cons`.
  class Cons
    include ISeq
    include IObj

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
end
