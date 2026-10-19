module RClojure
  module Core
    module Collections
      module_function

      def install(ns)
        define = ->(name, impl) { Core.define(ns, name, impl) }

        define.("list", ->(*items) { List.new(items) })
        define.("vector", ->(*items) { Vector.new(items) })
        define.("hash-set", ->(*items) { Set.new(items) })
        define.("hash-map", lambda { |*kvs|
          raise ArgumentError, "No value supplied for key: #{Printer.pr_str(kvs.last)}" if kvs.size.odd?

          Map.new(kvs.each_slice(2).to_h)
        })
        define.("vec", ->(coll) { Vector.new(RClojure.items(coll)) })
        define.("set", ->(coll) { Set.new(RClojure.items(coll)) })

        define.("seq", ->(coll) { RClojure.seq(coll) })
        define.("first", ->(coll) { RClojure.items(coll).first })
        define.("rest", ->(coll) { List.new(RClojure.items(coll).drop(1)) })
        define.("next", lambda { |coll|
          items = RClojure.items(coll)
          items.size > 1 ? List.new(items.drop(1)) : nil
        })
        define.("cons", ->(item, coll) { List.new([item, *RClojure.items(coll)]) })
        define.("concat", ->(*colls) { List.new(colls.flat_map { |coll| RClojure.items(coll) }) })
        define.("conj", lambda { |*args|
          return Vector[] if args.empty?

          coll, *items = args
          items.reduce(coll) { |acc, item| conj(acc, item) }
        })
        define.("count", ->(coll) { count(coll) })
        define.("empty?", ->(coll) { coll.is_a?(::String) ? coll.empty? : RClojure.items(coll).empty? })
        define.("nth", ->(coll, index, *not_found) { nth(coll, index, not_found) })
        define.("peek", ->(coll) { coll&.peek })
        define.("pop", ->(coll) { coll&.pop })

        define.("get", ->(coll, key, default = nil) { RClojure.get(coll, key, default) })
        define.("contains?", ->(coll, key) { contains?(coll, key) })
        define.("assoc", lambda { |coll, key, value, *kvs|
          if kvs.size.odd?
            raise ArgumentError, "assoc expects even number of arguments after map/vector, found odd number"
          end

          [key, value, *kvs].each_slice(2).reduce(coll || Map[]) { |acc, (k, v)| acc.assoc(k, v) }
        })
        define.("dissoc", ->(map, *keys) { map && keys.reduce(map) { |acc, key| acc.dissoc(key) } })
        define.("disj", ->(set, *items) { set && items.reduce(set) { |acc, item| acc.disj(item) } })
        define.("keys", ->(map) { map && RClojure.seq(List.new(map.keys)) })
        define.("vals", ->(map) { map && RClojure.seq(List.new(map.values)) })
        define.("key", ->(entry) { entry[0] })
        define.("val", ->(entry) { entry[1] })

        define.("reduce", lambda { |fn, *args|
          raise ArityError, "Wrong number of args (#{args.size + 1}) passed to: clojure.core/reduce" unless args.size.between?(1, 2)

          items = RClojure.items(args.last)
          if args.size == 2
            items.reduce(args.first) { |acc, item| RClojure.invoke(fn, [acc, item]) }
          elsif items.empty?
            RClojure.invoke(fn, [])
          else
            items.drop(1).reduce(items.first) { |acc, item| RClojure.invoke(fn, [acc, item]) }
          end
        })

        define.("coll?", ->(x) { x.is_a?(Sequential) || x.is_a?(Map) || x.is_a?(Set) })
        define.("sequential?", ->(x) { x.is_a?(Sequential) })
        define.("seq?", ->(x) { x.is_a?(List) })
        define.("list?", ->(x) { x.is_a?(List) })
        define.("vector?", ->(x) { x.is_a?(Vector) })
        define.("map?", ->(x) { x.is_a?(Map) })
        define.("set?", ->(x) { x.is_a?(Set) })
      end

      def conj(coll, item)
        case coll
        when nil then List[item]
        when Map then conj_map(coll, item)
        when List, Vector, Set then coll.conj(item)
        else raise Error, "Don't know how to conj onto: #{coll.class.name}"
        end
      end

      def conj_map(map, item)
        case item
        when nil then map
        when Map then item.reduce(map) { |acc, (key, value)| acc.assoc(key, value) }
        when Vector
          raise ArgumentError, "Vector arg to map conj must be a pair" unless item.size == 2

          map.assoc(item[0], item[1])
        else raise ArgumentError, "Can't conj #{Printer.pr_str(item)} onto a map"
        end
      end

      def count(coll)
        case coll
        when nil then 0
        when ::String then coll.length
        when Sequential, Map, Set, Array, Hash then coll.size
        else raise Error, "count not supported on this type: #{coll.class.name}"
        end
      end

      def nth(coll, index, not_found)
        if coll.is_a?(Sequential) && index.is_a?(Integer) && index.between?(0, coll.size - 1)
          coll.to_a[index]
        elsif !not_found.empty?
          not_found.first
        elsif coll.nil?
          nil
        else
          raise IndexError, "Index #{index} out of bounds"
        end
      end

      def contains?(coll, key)
        case coll
        when nil then false
        when Map then coll.key?(key)
        when Set then coll.include?(key)
        when Vector then key.is_a?(Integer) && key.between?(0, coll.size - 1)
        else raise ArgumentError, "contains? not supported on type: #{coll.class.name}"
        end
      end
    end
  end
end
