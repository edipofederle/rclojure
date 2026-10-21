require "test_helper"

# Checks the persistent collections against Ruby's Array and Hash, at
# sizes crossing the tries' boundaries.
class TestCollections < Minitest::Test
  include RClojure

  # Keys that all hash alike, to exercise HashTrie's collision nodes.
  CollidingKey = Struct.new(:id) do
    def hash
      42
    end
  end

  def setup
    @random = Random.new(1234)
  end

  # Whatever conj/pop/assoc did, the trie must have the shape Vector.new
  # gives the same items: no stale leaves, no needless levels.
  def assert_canonical(vector)
    expected = Vector.new(vector.to_a)
    %i[@size @shift @root @tail].each do |ivar|
      assert_equal expected.instance_variable_get(ivar), vector.instance_variable_get(ivar), "#{ivar} of a #{vector.size}-item vector"
    end
  end

  def test_vector_conj_nth_and_pop_across_trie_levels
    vector = Vector[]
    model = []
    versions = []
    33_000.times do |i|
      vector = vector.conj(i)
      model << i
      versions << [vector, i + 1] if [1, 32, 33, 1024, 1025, 1056, 32_768, 32_800].include?(i + 1)
    end
    assert_equal model.size, vector.size
    assert_equal model, vector.to_a
    [0, 31, 32, 1023, 1024, 32_767, 32_768, 32_999].each { |i| assert_equal i, vector[i] }
    assert_nil vector[33_000]
    assert_nil vector[-1]
    # older versions are unaffected
    versions.each { |version, size| assert_equal (0...size).to_a, version.to_a }
    versions.each { |version, _| assert_canonical version }

    until vector.empty?
      vector = vector.pop
      model.pop
      next unless (model.size % 997).zero? || model.size < 70

      assert_equal model.size, vector.size
      assert_equal model.last, vector.peek
      assert_equal model, vector.to_a
      assert_canonical vector
    end
    assert_raises(Error) { vector.pop }
  end

  def test_vector_built_from_an_array_matches_one_built_by_conj
    [0, 1, 31, 32, 33, 64, 65, 1023, 1024, 1025, 1056, 1057, 33_000].each do |size|
      items = (0...size).to_a
      built = Vector.new(items)
      conjed = items.reduce(Vector[]) { |v, item| v.conj(item) }
      assert_equal conjed, built
      assert_equal items, built.to_a
      assert_equal items + [:x], built.conj(:x).to_a
      assert_equal items[0...-1], built.pop.to_a unless size.zero?
    end
  end

  def test_vector_assoc
    model = (0...2000).to_a
    vector = Vector.new(model)
    original = vector
    500.times do
      index = @random.rand(model.size)
      vector = vector.assoc(index, -index)
      model[index] = -index
    end
    assert_equal model, vector.to_a
    assert_equal (0...2000).to_a, original.to_a
    assert_equal model + [:end], vector.assoc(2000, :end).to_a
    assert_raises(IndexError) { vector.assoc(2001, :x) }
  end

  def test_vector_seq_walks_the_leaves
    vector = Vector.new((0...1100).to_a)
    assert_equal (0...1100).to_a, RClojure.items(vector.seq)
    assert_equal 1100, vector.seq.size
    assert_equal (500...1100).to_a, RClojure.items(RClojure.seq(vector).then { |s| 500.times.reduce(s) { |acc, _| acc.next } })
  end

  def test_map_matches_hash_under_random_assoc_and_dissoc
    map = Map[]
    model = {}
    keys = (0...300).to_a + (0...20).map { |i| CollidingKey.new(i) } + [nil, "s", :k, 1.0]
    snapshots = []
    6000.times do |step|
      key = keys.sample(random: @random)
      if @random.rand < 0.65
        map = map.assoc(key, step)
        model[key] = step
      else
        map = map.dissoc(key)
        model.delete(key)
      end
      snapshots << [map, model.dup] if (step % 1000).zero?
      next unless (step % 250).zero?

      assert_equal model.size, map.size
      assert_equal model, map.to_h
      keys.each { |k| assert_equal model.key?(k), map.key?(k) }
    end
    model.each { |key, value| assert_equal value, map[key] }
    snapshots.each { |snapshot, expected| assert_equal expected, snapshot.to_h }
  end

  def test_maps_equal_across_representations_hash_alike
    big = Map.new((0...20).to_h { |i| [i, i] })
    shrunk = (3...20).reduce(big) { |map, i| map.dissoc(i) }
    small = Map[{ 0 => 0, 1 => 1, 2 => 2 }]
    assert_equal small, shrunk
    assert_equal shrunk, small
    assert_equal small.hash, shrunk.hash
    assert_equal :found, Map[{ shrunk => :found }][small]
  end

  def test_map_switches_to_a_trie_past_eight_entries
    map = Map.new((1..8).to_h { |i| [i, i] })
    assert_equal (1..8).to_a, map.keys # small maps keep insertion order
    bigger = map.assoc(9, 9)
    assert_equal 9, bigger.size
    assert_equal (1..9).to_a, bigger.keys.sort
    assert_equal 8, map.size
    assert_same bigger, bigger.assoc(9, 9)
    assert_same bigger, bigger.dissoc(:absent)
  end

  def test_colliding_keys
    a = CollidingKey.new(1)
    b = CollidingKey.new(2)
    c = CollidingKey.new(3)
    map = Map.new((0...10).to_h { |i| [i, i] }).assoc(a, :a).assoc(b, :b).assoc(c, :c)
    assert_equal %i[a b c], [map[a], map[b], map[c]]
    map = map.dissoc(b)
    assert_nil map[b]
    assert_equal %i[a c], [map[a], map[c]]
    map = map.dissoc(a).dissoc(c)
    assert_equal 10, map.size
    refute map.key?(c)
  end

  def test_sets
    set = Set[]
    model = []
    3000.times do
      item = @random.rand(400)
      if @random.rand < 0.6
        set = set.conj(item)
        model |= [item]
      else
        set = set.disj(item)
        model -= [item]
      end
    end
    assert_equal model.sort, set.to_a.sort
    assert_equal model.size, set.size
    assert_equal Set.new(model), set
    assert_equal Set.new(model).hash, set.hash
    model.each { |item| assert_equal item, set.call(item) }
  end

  def test_large_collections_from_rclojure
    runtime = Runtime.new
    assert_equal 50_000, runtime.eval_string("(count (reduce conj [] (range 50000)))")
    assert_equal 49_999, runtime.eval_string("(peek (into [] (range 50000)))")
    assert_equal 5000, runtime.eval_string("(count (reduce (fn [m i] (assoc m i (* i i))) {} (range 5000)))")
    assert_equal 81, runtime.eval_string("(get (zipmap (range 100) (map (fn [x] (* x x)) (range 100))) 9)")
    assert_equal 1000, runtime.eval_string("(count (into \#{} (range 1000)))")
  end
end
