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
end
