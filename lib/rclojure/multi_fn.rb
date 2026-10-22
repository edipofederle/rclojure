module RClojure
  # A multimethod, ported from Clojure's MultiFn: calling it applies the
  # dispatch fn to the args, then the method whose dispatch value the
  # result `isa?` (in hierarchy, a reference such as a var holding the
  # hierarchy map), preferring the most specific one; ambiguity that
  # prefer-method doesn't settle is an error. The chosen method is cached
  # per dispatch value until the methods, preferences or hierarchy change.
  #
  # isa and parents are clojure.core's isa? and parents vars, which
  # Clojure's MultiFn also calls.
  class MultiFn
    attr_reader :name, :method_table, :prefer_table

    def initialize(name, dispatch_fn, default_dispatch_value, hierarchy, isa, parents)
      @name = name
      @dispatch_fn = dispatch_fn
      @default_dispatch_value = default_dispatch_value
      @hierarchy = hierarchy
      @isa = isa
      @parents = parents
      @lock = Mutex.new
      @method_table = Map[]
      @prefer_table = Map[]
      reset_cache
    end

    def call(*args)
      dispatch_value = RClojure.invoke(@dispatch_fn, args)
      method = get_method(dispatch_value) or
        raise ArgumentError, "No method in multimethod '#{@name}' for dispatch value: #{Printer.pr_str(dispatch_value)}"

      RClojure.invoke(method, args)
    end

    def add_method(dispatch_value, method)
      change { @method_table = @method_table.assoc(dispatch_value, method) }
    end

    def remove_method(dispatch_value)
      change { @method_table = @method_table.dissoc(dispatch_value) }
    end

    def reset
      change do
        @method_table = Map[]
        @prefer_table = Map[]
      end
    end

    def prefer_method(x, y)
      change do
        if prefers?(@hierarchy.deref, y, x)
          raise Error, "Preference conflict in multimethod '#{@name}': " \
                       "#{Printer.pr_str(y)} is already preferred to #{Printer.pr_str(x)}"
        end

        @prefer_table = @prefer_table.assoc(x, @prefer_table.call(x, Set[]).conj(y))
      end
    end

    # The method for dispatch_value (the default method if none matches),
    # or nil.
    def get_method(dispatch_value)
      hierarchy = @hierarchy.deref
      @lock.synchronize { reset_cache unless hierarchy.equal?(@cached_hierarchy) }
      @method_cache.fetch(dispatch_value) { find_and_cache_best_method(dispatch_value, hierarchy) }
    end

    def to_s
      "#<multifn #{@name}>"
    end
    alias inspect to_s

    private

    def change
      @lock.synchronize do
        yield
        reset_cache
      end
      self
    end

    def reset_cache
      @method_cache = {}
      @cached_hierarchy = @hierarchy.deref
    end

    def find_and_cache_best_method(dispatch_value, hierarchy)
      best_key = nil
      best_method = nil
      @method_table.each do |key, method|
        next unless isa?(hierarchy, dispatch_value, key)

        if best_key.nil? || dominates?(hierarchy, key, best_key)
          best_key = key
          best_method = method
        end
        next if dominates?(hierarchy, best_key, key)

        raise ArgumentError, "Multiple methods in multimethod '#{@name}' match dispatch value: " \
                             "#{Printer.pr_str(dispatch_value)} -> #{Printer.pr_str(key)} and " \
                             "#{Printer.pr_str(best_key)}, and neither is preferred"
      end
      best_method ||= @method_table[@default_dispatch_value]
      @lock.synchronize { @method_cache[dispatch_value] = best_method if best_method }
      best_method
    end

    def isa?(hierarchy, child, parent)
      RClojure.truthy?(RClojure.invoke(@isa, [hierarchy, child, parent]))
    end

    def dominates?(hierarchy, x, y)
      prefers?(hierarchy, x, y) || isa?(hierarchy, x, y)
    end

    # Whether x is preferred to y, directly or through their parents.
    def prefers?(hierarchy, x, y)
      preferred = @prefer_table[x]
      return true if preferred&.include?(y)

      RClojure.items(RClojure.invoke(@parents, [hierarchy, y])).any? { |parent| prefers?(hierarchy, x, parent) } ||
        RClojure.items(RClojure.invoke(@parents, [hierarchy, x])).any? { |parent| prefers?(hierarchy, parent, y) }
    end
  end
end
