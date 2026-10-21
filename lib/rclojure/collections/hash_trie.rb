module RClojure
  # The hash array mapped trie behind large maps, ported from Clojure's
  # PersistentHashMap (BitmapIndexedNode and HashCollisionNode; Clojure's
  # ArrayNode, an optimization for dense nodes, is left out). Keys are
  # compared like Ruby Hash keys, with #hash and #eql?.
  #
  # Nodes are immutable: assoc and without return a new node, or the same
  # node when nothing changed. without returns nil when the node empties.
  module HashTrie
    # Marks a slot holding a child node rather than a key.
    SUBNODE = Object.new.freeze
    # Ruby has no Integer#bit_count, so popcounts go through a byte table.
    BIT_COUNTS = (0..255).map { |byte| byte.to_s(2).count("1") }.freeze

    module_function

    # Clojure uses 32-bit hashes; so does the trie.
    def hash_of(key)
      key.hash & 0xFFFFFFFF
    end

    def bit_count(bits)
      BIT_COUNTS[bits & 0xFF] + BIT_COUNTS[(bits >> 8) & 0xFF] +
        BIT_COUNTS[(bits >> 16) & 0xFF] + BIT_COUNTS[bits >> 24]
    end

    def bitpos(hash, shift)
      1 << ((hash >> shift) & 0x1F)
    end

    # A node holding two entries whose keys differ.
    def create_node(shift, key1, value1, hash2, key2, value2)
      hash1 = hash_of(key1)
      return CollisionNode.new(hash1, [key1, value1, key2, value2].freeze) if hash1 == hash2

      added = [false]
      BitmapNode::EMPTY.assoc(shift, hash1, key1, value1, added).assoc(shift, hash2, key2, value2, added)
    end

    # Up to 32 slots, one per 5-bit chunk of the hash at this level; the
    # bitmap says which are present. array holds a key/value pair per
    # slot, or SUBNODE followed by a child node.
    class BitmapNode
      def initialize(bitmap, array)
        @bitmap = bitmap
        @array = array
        freeze
      end

      EMPTY = new(0, [].freeze)

      def find(shift, hash, key, not_found)
        bit = HashTrie.bitpos(hash, shift)
        return not_found if (@bitmap & bit).zero?

        i = 2 * index(bit)
        slot_key = @array[i]
        value = @array[i + 1]
        return value.find(shift + 5, hash, key, not_found) if slot_key.equal?(HashTrie::SUBNODE)

        key.eql?(slot_key) ? value : not_found
      end

      # Sets added[0] when key is new.
      def assoc(shift, hash, key, value, added)
        bit = HashTrie.bitpos(hash, shift)
        i = 2 * index(bit)
        if (@bitmap & bit).zero?
          added[0] = true
          return BitmapNode.new(@bitmap | bit, (@array[0, i] + [key, value] + @array[i..]).freeze)
        end

        slot_key = @array[i]
        slot_value = @array[i + 1]
        if slot_key.equal?(HashTrie::SUBNODE)
          node = slot_value.assoc(shift + 5, hash, key, value, added)
          return node.equal?(slot_value) ? self : with(i + 1, node)
        end
        return slot_value.equal?(value) ? self : with(i + 1, value) if key.eql?(slot_key)

        added[0] = true
        node = HashTrie.create_node(shift + 5, slot_key, slot_value, hash, key, value)
        array = @array.dup
        array[i] = HashTrie::SUBNODE
        array[i + 1] = node
        BitmapNode.new(@bitmap, array.freeze)
      end

      def without(shift, hash, key)
        bit = HashTrie.bitpos(hash, shift)
        return self if (@bitmap & bit).zero?

        i = 2 * index(bit)
        slot_key = @array[i]
        slot_value = @array[i + 1]
        if slot_key.equal?(HashTrie::SUBNODE)
          node = slot_value.without(shift + 5, hash, key)
          return self if node.equal?(slot_value)
          return with(i + 1, node) if node
        elsif !key.eql?(slot_key)
          return self
        end
        return nil if @bitmap == bit

        BitmapNode.new(@bitmap ^ bit, (@array[0, i] + @array[(i + 2)..]).freeze)
      end

      def each(&block)
        @array.each_slice(2) do |key, value|
          key.equal?(HashTrie::SUBNODE) ? value.each(&block) : yield(key, value)
        end
      end

      private

      def index(bit)
        HashTrie.bit_count(@bitmap & (bit - 1))
      end

      def with(i, value)
        array = @array.dup
        array[i] = value
        BitmapNode.new(@bitmap, array.freeze)
      end
    end

    # Entries whose keys all have the same 32-bit hash.
    class CollisionNode
      def initialize(hash, array)
        @hash = hash
        @array = array
        freeze
      end

      def find(_shift, _hash, key, not_found)
        i = index(key)
        i ? @array[i + 1] : not_found
      end

      def assoc(shift, hash, key, value, added)
        unless hash == @hash
          # Nest this node one level down, under a bitmap node.
          wrapper = BitmapNode.new(HashTrie.bitpos(@hash, shift), [HashTrie::SUBNODE, self].freeze)
          return wrapper.assoc(shift, hash, key, value, added)
        end

        i = index(key)
        if i
          return self if @array[i + 1].equal?(value)

          array = @array.dup
          array[i + 1] = value
          return CollisionNode.new(@hash, array.freeze)
        end
        added[0] = true
        CollisionNode.new(@hash, (@array + [key, value]).freeze)
      end

      def without(_shift, _hash, key)
        i = index(key)
        return self unless i
        return nil if @array.size == 2

        CollisionNode.new(@hash, (@array[0, i] + @array[(i + 2)..]).freeze)
      end

      def each(&block)
        @array.each_slice(2) { |key, value| yield(key, value) }
      end

      private

      def index(key)
        (0...@array.size).step(2).find { |i| key.eql?(@array[i]) }
      end
    end
  end
end
