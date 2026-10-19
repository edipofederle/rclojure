module RClojure
  # Clojure's atom: a reference updated atomically with swap!/reset!.
  class Atom
    def initialize(value)
      @value = value
      @lock = Mutex.new
    end

    def deref
      @value
    end

    def reset(value)
      @lock.synchronize { @value = value }
    end

    # Applies fn outside the lock and retries if another thread changed the
    # value meanwhile, so fn may run more than once (as in Clojure).
    def swap(fn, args)
      loop do
        old = @value
        new = RClojure.invoke(fn, [old, *args])
        @lock.synchronize do
          if @value.equal?(old)
            @value = new
            return new
          end
        end
      end
    end

    def inspect
      "#<RClojure::Atom #{@value.inspect}>"
    end
  end
end
