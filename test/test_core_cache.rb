require "test_helper"
require "fileutils"

class TestCoreCache < Minitest::Test
  include RClojure
  include RClojureTestHelpers

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "core-#{CoreCache.digest}.bin")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_first_runtime_writes_the_cache_and_later_ones_use_it
    Runtime.new(cache_dir: @dir)
    assert File.file?(@path)
    refute_nil CoreCache.new(@dir).load(Runtime.new(cache_dir: nil))

    runtime = Runtime.new(cache_dir: @dir)
    assert_equal [1, 3], runtime.eval_string("(vec (for [x (range 4) :when (odd? x)] x))").to_a
    assert_equal "#'clojure.core/map", runtime.eval_string("(str (var map))")
    assert_raises(CompilerError) { runtime.eval_string("(clojure.core/check-bindings 1 2)") }
    assert_equal read("(if a (do b))"), runtime.eval_string("(macroexpand-1 '(when a b))")
  end

  def test_cached_runtimes_are_independent
    Runtime.new(cache_dir: @dir)
    first = Runtime.new(cache_dir: @dir)
    second = Runtime.new(cache_dir: @dir)
    first.eval_string("(intern 'clojure.core 'inc (fn [x] :changed))")
    assert_equal :changed, first.eval_string("(clojure.core/inc 1)")
    assert_equal 2, second.eval_string("(clojure.core/inc 1)")
  end

  def test_cached_runtimes_match_uncached_ones
    Runtime.new(cache_dir: @dir)
    cached = Runtime.new(cache_dir: @dir)
    uncached = Runtime.new(cache_dir: nil)
    assert_equal uncached.eval_string("(gensym)"), cached.eval_string("(gensym)")
    assert_equal uncached.eval_string("(set (keys (ns-publics 'clojure.core)))"),
                 cached.eval_string("(set (keys (ns-publics 'clojure.core)))")
  end

  def test_unusable_caches_fall_back_to_source
    File.write(@path, "not a marshal dump")
    assert_equal 2, Runtime.new(cache_dir: @dir).eval_string("(inc 1)")

    blocked = File.join(@dir, "a-file")
    File.write(blocked, "")
    assert_equal 2, Runtime.new(cache_dir: blocked).eval_string("(inc 1)")
  end

  def test_stale_caches_are_replaced
    stale = File.join(@dir, "core-0000.bin")
    File.write(stale, "old")
    Runtime.new(cache_dir: @dir)
    refute File.exist?(stale)
    assert File.file?(@path)
  end

  def test_no_cache_dir_means_no_caching
    Runtime.new(cache_dir: nil)
    assert_empty Dir.children(@dir)
  end

  def test_values_come_back_frozen
    [Symbol.parse("a/b"), List[1, List[2]], List::EMPTY, Vector[1, "s"], Map[{ a: 1 }], Set[1]].each do |value|
      copy = Marshal.load(Marshal.dump(value))
      assert_equal value, copy
      assert_predicate copy, :frozen?
    end
  end
end
