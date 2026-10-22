module RClojure
  # What `range` returns for a non-zero step: like Clojure's LongRange and
  # Range, items are computed on demand and integer ranges are counted.
  # Never empty; `create` returns nil when there would be no items.
  class RangeSeq
    include ISeq
    include IObj

    def self.create(start, finish, step)
      new(start, finish, step) if in_range?(start, finish, step)
    end

    def self.in_range?(value, finish, step)
      step.positive? ? value < finish : value > finish
    end

    def initialize(start, finish, step)
      @start = start
      @finish = finish
      @step = step
      freeze
    end

    def first
      @start
    end

    def rest
      self.next || List::EMPTY
    end

    def next
      following = @start + @step
      RangeSeq.new(following, @finish, @step) if RangeSeq.in_range?(following, @finish, @step)
    end

    def seq
      self
    end

    def size
      exact? ? (@finish - @start).quo(@step).ceil : super
    end

    def counted?
      exact?
    end

    def inspect
      "#<RClojure::RangeSeq #{@start} #{@finish} #{@step}>"
    end

    private

    # Float ranges are walked, since summing steps can drift from the
    # count that division would give.
    def exact?
      [@start, @finish, @step].none?(Float)
    end
  end
end
