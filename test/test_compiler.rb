require "test_helper"

# Cases that are easy to get wrong when compiling to Ruby: Ruby closures
# capture variables, loops reuse them, and tail positions become
# break/next.
class TestCompiler < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def test_closures_in_loops_keep_their_values
    assert_ev Vector[0, 1, 2], "(loop [i 0 fs []] (if (< i 3) (recur (inc i) (conj fs (fn [] i))) (mapv (fn [f] (f)) fs)))"
    assert_ev Vector[0, 10, 20],
              "(loop [i 0 fs []] (if (< i 3) (let [x (* 10 i)] (recur (inc i) (conj fs (fn [] x)))) (mapv (fn [f] (f)) fs)))"
    # an inner loop's closure over an outer loop's local
    assert_ev Vector[Vector[0, 0], Vector[1, 0], Vector[1, 1]],
              "(loop [i 0 fs []]
                 (if (< i 2)
                   (recur (inc i) (loop [j 0 fs fs] (if (<= j i) (recur (inc j) (conj fs (fn [] [i j]))) fs)))
                   (mapv (fn [f] (f)) fs)))"
    # a fn nested in a fn, both made in the loop
    assert_ev Vector[0, 1], "(loop [i 0 fs []] (if (< i 2) (recur (inc i) (conj fs (fn [] (fn [] i)))) (mapv (fn [f] ((f))) fs)))"
  end

  def test_named_fns_in_loops_call_themselves
    assert_ev Vector[0, 1, 2],
              "(loop [i 0 fs []]
                 (if (< i 3)
                   (recur (inc i) (conj fs (fn me [n] (if (pos? n) (me (dec n)) i))))
                   (mapv (fn [f] (f 3)) fs)))"
  end

  def test_closures_over_recurring_fn_params
    assert_ev Vector[3, 2, 1],
              "((fn [n fs] (if (pos? n) (recur (dec n) (conj fs (fn [] n))) (mapv (fn [f] (f)) fs))) 3 [])"
  end

  def test_closures_over_catch_bindings_in_loops
    assert_ev Vector["a", "b"],
              "(loop [ms [\"a\" \"b\"] fs []]
                 (if (seq ms)
                   (recur (rest ms) (conj fs (try (throw (ex-info (first ms) {})) (catch :default e (fn [] (ex-message e))))))
                   (mapv (fn [f] (f)) fs)))"
  end

  def test_recur_through_let_do_and_if
    assert_ev 10, "(loop [i 0] (let [j (inc i)] (do :ignored (if (< j 10) (recur j) j))))"
    assert_ev 6, "((fn [acc & xs] (if xs (recur (+ acc (first xs)) (next xs)) acc)) 0 1 2 3)"
    assert_ev Vector[2, 1], "(loop [a 1 b 2] (if (< a b) (recur b a) [a b]))"
  end

  def test_loops_and_trys_as_values
    assert_ev 4, "(+ 1 (loop [i 0] (if (< i 3) (recur (inc i)) i)))"
    assert_ev Vector[3, 3], "[(loop [i 0] (if (< i 3) (recur (inc i)) i)) (loop [i 0] (if (< i 3) (recur (inc i)) i))]"
    assert_ev :caught, "(loop [i 0] (if (< i 2) (recur (inc i)) (try (throw (ex-info \"x\" {})) (catch :default _ :caught))))"
    assert_ev 1, "(let [x (try 1 (finally :ignored))] x)"
    assert_ev nil, "((fn []))"
    assert_ev nil, "(loop [] nil)"
  end

  def test_unusual_local_names
    assert_ev 3, "(let [a->b 1 x? 2] (+ a->b x?))"
    assert_ev 6, "(let [*x* 1 +y+ 2 λ 3] (+ *x* +y+ λ))"
    assert_ev 3, "(let [end 1 class 2 self 3 nil? 4] (- (+ end class self nil?) 7))"
    assert_ev 2, "(let [k 1 l_k__1 2] (+ k (dec l_k__1)))"
    assert_ev 2, "(let [x 1] (let [x (inc x)] x))"
  end

  def test_host_calls_with_odd_method_names
    assert_ev String, '(.class "s")'
    assert_ev 3, "(. 1 + 2)"
    assert_ev "abab", "(. \"ab\" * 2)"
    assert_ev true, "(. 1 == 1)"
  end

  def test_literals
    assert_ev(-1, "-1")
    assert_ev(-0.5, "-0.5")
    assert_ev 1e20, "1e20"
    assert_ev 2**70, "1180591620717411303424"
    assert_ev :"a/b", ":a/b"
    assert_ev :+, ":+"
    assert_ev Float::INFINITY, "(/ 1.0 0)"
  end

  def test_string_literals_stay_frozen_and_shared
    assert_raises(FrozenError) { ev('(.concat "abc" "d")') }
    ev '(defn s [] "same")'
    assert_ev true, "(identical? (s) (s))"
  end
end
