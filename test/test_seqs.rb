require "test_helper"

class TestSeqs < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def setup
    super
    ev "(defn nums [n] (lazy-seq (cons n (nums (inc n)))))"
    ev "(defn upto [n end] (lazy-seq (when (< n end) (cons n (upto (inc n) end)))))"
  end

  def test_lazy_seq_defers_and_caches_its_body
    ev "(def calls (atom 0))"
    ev "(def s (lazy-seq (swap! calls inc) [1 2]))"
    assert_ev 0, "@calls"
    assert_ev false, "(realized? s)"
    assert_ev 1, "(first s)"
    assert_ev List[1, 2], "s"
    assert_ev 1, "@calls"
    assert_ev true, "(realized? s)"
  end

  def test_failed_realization_is_retried
    ev "(def calls (atom 0))"
    ev "(def s (lazy-seq (swap! calls inc) (throw (ex-info \"boom\" {}))))"
    assert_raises(ExceptionInfo) { ev("(seq s)") }
    assert_raises(ExceptionInfo) { ev("(seq s)") }
    assert_ev 2, "@calls"
  end

  def test_infinite_seqs
    assert_ev 1, "(second (nums 0))"
    assert_ev 1000, "(nth (nums 0) 1000)"
    assert_ev Vector[0, 1, List[2, 3]], "(let [[a b & more] (nums 0)] [a b (list (first more) (second more))])"
  end

  def test_long_seqs_do_not_grow_the_stack
    assert_ev 49_995_000, "(reduce + (upto 0 10000))"
    assert_ev 10_000, "(count (upto 0 10000))"
    assert_ev :deep, "(first (loop [s [:deep] n 0] (if (< n 10000) (recur (lazy-seq s) (inc n)) s)))"
  end

  def test_empty_lazy_seqs
    assert_ev nil, "(seq (lazy-seq nil))"
    assert_ev nil, "(seq (lazy-seq []))"
    assert_ev true, "(empty? (lazy-seq nil))"
    assert_ev List::EMPTY, "(rest (lazy-seq nil))"
    assert_ev nil, "(next (lazy-seq [1]))"
    assert_ev "()", "(pr-str (lazy-seq nil))"
    assert_ev true, "(boolean (lazy-seq nil))"
  end

  def test_equality_and_hashing_across_seq_types
    assert_ev true, "(= [1 2] (lazy-seq [1 2]) '(1 2) (cons 1 [2]) (seq [1 2]))"
    assert_ev true, "(= () (lazy-seq nil))"
    assert_ev false, "(= [1 2] (upto 0 3))"
    assert_ev false, "(= (upto 0 3) [0 1])"
    assert_ev false, "(= (lazy-seq [1]) [1.0])"
    assert_ev true, "(= (hash [1 2]) (hash (lazy-seq [1 2])) (hash (cons 1 '(2))))"
    assert_ev :found, "(get {[1 2] :found} (lazy-seq [1 2]))"
  end

  def test_seq_types
    assert_ev Vector[true, false], "[(seq? (lazy-seq nil)) (list? (lazy-seq nil))]"
    assert_ev Vector[true, false], "[(seq? (cons 1 nil)) (list? (cons 1 [2]))]"
    assert_ev Vector[true, false], "[(seq? (seq [1])) (list? (seq [1]))]"
    assert_ev Vector[true, false], "((fn [& xs] [(seq? xs) (list? xs)]) 1 2)"
    assert_ev true, "(coll? (lazy-seq nil))"
    assert_ev true, "(sequential? (cons 1 nil))"
  end

  def test_cons_and_conj_do_not_realize
    ev "(def calls (atom 0))"
    ev "(def s (cons 0 (lazy-seq (swap! calls inc) [1])))"
    assert_ev 0, "(first s)"
    assert_ev 0, "@calls"
    assert_ev List[-1, 0, 1], "(conj s -1)"
    assert_ev List[0, 1], "(conj (lazy-seq [1]) 0)"
  end

  def test_seq_functions_on_lazy_seqs
    assert_ev "(0 1 2)", "(pr-str (upto 0 3))"
    assert_ev Vector[0, 1, 2], "(vec (upto 0 3))"
    assert_ev Vector[1, 2], "(into [] (rest (upto 0 3)))"
    assert_ev 2, "(last (upto 0 3))"
    assert_ev List[2, 1, 0], "(reverse (upto 0 3))"
    assert_ev 3, "(apply + (upto 0 3))"
    assert_ev :none, "(nth (upto 0 3) 3 :none)"
    assert_raises(IndexError) { ev("(nth (upto 0 3) 3)") }
    assert_ev Vector[0, 1, 2], "(let [v (atom [])] (doseq [x (upto 0 3)] (swap! v conj x)) @v)"
  end

  def test_macros_may_return_any_seq
    ev "(defmacro via-cons [] (cons 'do (list 1 2)))"
    ev "(defmacro via-lazy-seq [] (lazy-seq (list '+ 1 2)))"
    assert_ev 2, "(via-cons)"
    assert_ev 3, "(via-lazy-seq)"
    assert_ev 3, "(eval (cons '+ [1 2]))"
  end

  def test_ruby_collections_are_seqable
    assert_ev List[:x, :x], "(seq (Array/new 2 :x))"
    assert_ev List[:x], "(rest (Array/new 2 :x))"
    assert_ev nil, "(seq (Hash/new))"
    assert_raises(Error) { ev("(seq 1)") }
  end

  def test_map
    assert_ev List[2, 3, 4], "(map inc [1 2 3])"
    assert_ev List[11, 22], "(map + [1 2] [10 20 30])"
    assert_ev List[Vector[1, :a, :x], Vector[2, :b, :y]], "(map vector [1 2] [:a :b] [:x :y])"
    assert_ev List[10], "(map + [1] [2] [3] [4 5])"
    assert_ev List[1, 2, 3], "(take 3 (map inc (range)))"
    assert_ev List::EMPTY, "(map inc nil)"
  end

  # Clojure realizes vector seqs 32 items at a time; rclojure never chunks.
  def test_map_realizes_one_item_at_a_time
    ev "(def calls (atom 0))"
    ev "(def s (map (fn [x] (swap! calls inc) x) [1 2 3]))"
    assert_ev 0, "@calls"
    assert_ev 1, "(first s)"
    assert_ev 1, "@calls"
    assert_ev nil, "(dorun s)"
    assert_ev 3, "@calls"
  end

  def test_filtering
    assert_ev List[1, 3, 5, 7, 9], "(filter odd? (range 10))"
    assert_ev List[0, 2, 4], "(take 3 (filter even? (range)))"
    assert_ev List[2], "(remove odd? [1 2 3])"
    assert_ev List[1, 9], "(keep (fn [x] (when (odd? x) (* x x))) [1 2 3])"
    assert_ev List[false], "(keep (fn [x] false) [1])"
    assert_ev List[1, 2, 3], "(distinct [1 2 1 3 2])"
    assert_ev List[1, 2, 3], "(take 3 (distinct (cycle [1 2 3 4])))"
    assert_ev 10_000, "(count (filter even? (range 20000)))"
  end

  def test_mapping_variants
    assert_ev List[Vector[0, :a], Vector[1, :b]], "(map-indexed vector [:a :b])"
    assert_ev List[1, 1, 2, 2], "(mapcat (fn [x] [x x]) [1 2])"
    assert_ev List[1, :a, 2, :b], "(mapcat list [1 2] [:a :b])"
    assert_ev Vector[2, 3], "(mapv inc '(1 2))"
    assert_ev Vector[11, 22], "(mapv + [1 2] [10 20])"
    assert_ev Vector[1, 3], "(filterv odd? (range 4))"
  end

  def test_take_and_drop
    assert_ev List[1, 2], "(take 2 [1 2 3])"
    assert_ev List::EMPTY, "(take 0 [1])"
    assert_ev List[1], "(take 5 [1])"
    assert_ev List[3], "(drop 2 [1 2 3])"
    assert_ev List[1], "(drop -1 [1])"
    assert_ev List[-1, -2], "(take-while neg? [-1 -2 0 -3])"
    assert_ev List[0, -2], "(drop-while neg? [-1 0 -2])"
    assert_ev List[0, 2, 4, 6], "(take-nth 2 (range 7))"
    assert_ev List[2, 3], "(take-last 2 [1 2 3])"
    assert_ev nil, "(take-last 2 [])"
    assert_ev List[1, 2], "(drop-last [1 2 3])"
    assert_ev Vector[List[1], List[2, 3]], "(split-at 1 [1 2 3])"
    assert_ev Vector[List[1, 3], List[2, 5]], "(split-with odd? [1 3 2 5])"
  end

  def test_generators
    assert_ev List[:x, :x, :x], "(repeat 3 :x)"
    assert_ev List[:y, :y], "(take 2 (repeat :y))"
    assert_ev List::EMPTY, "(repeat -1 :x)"
    assert_ev List[1, 1, 1], "(repeatedly 3 (constantly 1))"
    assert_ev List[5, 6, 7], "(take 3 (iterate inc 5))"
    assert_ev List[1, 2, 1, 2, 1], "(take 5 (cycle [1 2]))"
    assert_ev List::EMPTY, "(cycle [])"
    ev "(def calls (atom 0))"
    assert_ev 0, "(first (iterate (fn [x] (swap! calls inc) x) 0))"
    assert_ev 0, "@calls"
  end

  def test_range
    assert_ev List[0, 1, 2], "(range 3)"
    assert_ev List[1, 2, 3], "(range 1 4)"
    assert_ev List[0, 3, 6, 9], "(range 0 10 3)"
    assert_ev List[5, 3, 1], "(range 5 0 -2)"
    assert_ev List::EMPTY, "(range 0)"
    assert_ev List::EMPTY, "(range 3 3)"
    assert_ev List::EMPTY, "(range 3 1)"
    assert_ev List::EMPTY, "(range 7 7 0)"
    assert_ev List[1, 1, 1], "(take 3 (range 1 5 0))"
    assert_ev List[0, 1, 2], "(take 3 (range))"
    assert_ev List[0, Rational(1, 4), Rational(1, 2), Rational(3, 4)], "(range 0 1 1/4)"
    assert_ev List[0.0, 0.5], "(range 0.0 1.0 0.5)"
    assert_ev 4, "(count (range 0 10 3))"
    assert_ev 1_000_000, "(count (range 1000000))"
    assert_ev 3, "(nth (range 10) 3)"
    assert_ev 5050, "(reduce + (range 101))"
    assert_ev true, "(= (range 3) [0 1 2])"
  end

  def test_concat_and_friends
    assert_ev List[1, 2, 3], "(concat [1] '(2) nil [3])"
    assert_ev List::EMPTY, "(concat)"
    assert_ev List[1, 0, 1], "(take 3 (concat [1] (range)))"
    ev "(def calls (atom 0))"
    assert_ev 1, "(first (concat [1] (lazy-seq (swap! calls inc) [2])))"
    assert_ev 0, "@calls"
    assert_ev 1, "(first (lazy-cat [1] (throw (ex-info \"never\" {}))))"
    assert_ev List[1, :a, 2, :b], "(interleave [1 2 3] [:a :b])"
    assert_ev List[1, :a, :x, 2, :b, :y], "(interleave [1 2] [:a :b] [:x :y])"
    assert_ev List[1, :x, 2], "(interpose :x [1 2])"
    assert_ev List[0, :x, 1], "(take 3 (interpose :x (range)))"
  end

  def test_partition
    assert_ev List[List[1, 2], List[3, 4]], "(partition 2 [1 2 3 4 5])"
    assert_ev List[List[1, 2], List[2, 3]], "(partition 2 1 [1 2 3])"
    assert_ev List[List[1, 2], List[3, :pad]], "(partition 2 2 [:pad] [1 2 3])"
    assert_ev List[List[1, 2], List[3]], "(partition-all 2 [1 2 3])"
    assert_ev List[List[0, 1], List[2, 3]], "(take 2 (partition 2 (range)))"
  end

  def test_doall_and_dorun
    ev "(def calls (atom 0))"
    ev "(def s (map (fn [x] (swap! calls inc) x) [1 2 3]))"
    # like Clojure's, (dorun n coll) calls next n times, realizing n + 1 items
    assert_ev nil, "(dorun 1 s)"
    assert_ev 2, "@calls"
    assert_ev List[1, 2, 3], "(doall s)"
    assert_ev 3, "@calls"
  end

  def test_for
    assert_ev List[Vector[1, :a], Vector[1, :b], Vector[2, :a], Vector[2, :b]], "(for [x [1 2] y [:a :b]] [x y])"
    assert_ev List[1, 3], "(for [x (range 5) :when (odd? x)] x)"
    assert_ev List[10, 20], "(for [x [1 2] :let [y (* x 10)]] y)"
    assert_ev List[0, 1, 2], "(for [x (range 10) :while (< x 3)] x)"
    assert_ev List[Vector[2, 1], Vector[3, 1], Vector[3, 2]], "(for [x [1 2 3] y [1 2 3] :while (< y x)] [x y])"
    assert_ev List[0, 0, 1, 0, 1, 2], "(for [x [1 2 3] y (range x)] y)"
    assert_ev List[Vector[1, 0], Vector[2, 0], Vector[2, 1]], "(for [x [0 1 0 2] y (range x)] [x y])"
    assert_ev List[0, 1, 4], "(take 3 (for [x (range)] (* x x)))"
    assert_ev List[Vector[1, :a]], "(for [[k v] {:a 1}] [v k])"
    assert_ev List::EMPTY, "(for [x []] x)"
    assert_raises(CompilerError) { ev("(for [x [1] :until true] x)") }
  end

  def test_lazy_pipelines
    assert_ev 50_005_000, "(reduce + (map inc (range 10000)))"
    assert_ev List[0, 4, 16], "(->> (range) (filter even?) (map (fn [x] (* x x))) (take 3))"
  end
end
