require "test_helper"

class TestMacros < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def sym(text)
    Symbol.parse(text)
  end

  def test_syntax_quote_qualifies_symbols
    assert_ev List[sym("clojure.core/str"), sym("user/undefined-thing")], "`(str undefined-thing)"
    assert_ev List[sym("user/mine")], "(def mine 1) `(mine)"
    assert_ev List[sym("if"), sym("do"), sym("&"), sym("other.ns/x")], "`(if do & other.ns/x)"
  end

  def test_syntax_quote_unquote_and_splice
    assert_ev List[sym("clojure.core/+"), 3, 4, 5], "`(+ ~(+ 1 2) ~@[4 5])"
    assert_ev Vector[1, :k, "s", nil], "`[~1 :k \"s\" nil]"
    assert_ev Map[{ a: 2 }], "`{:a ~(inc 1)}"
    assert_ev Set[1], "`\#{~1}"
    assert_ev List::EMPTY, "`()"
    assert_ev List[sym("quote"), sym("user/x")], "`'x"
    assert_raises(CompilerError) { ev("`~@[1]") }
  end

  def test_auto_gensyms_are_consistent_within_one_syntax_quote
    form = ev("`(let [x# 1] x#)")
    binding = form.to_a[1]
    generated = binding.to_a.first
    assert_match(/\Ax__\d+__auto__\z/, generated.name)
    assert_equal generated, form.to_a[2]
    refute_equal generated, ev("`x#")
  end

  def test_nested_syntax_quote
    assert_ev sym("user/a"), "(eval ``a)"
  end

  def test_defmacro
    ev("(defmacro unless [test & body] `(if ~test nil (do ~@body)))")
    assert_ev :ran, "(unless false :ran)"
    assert_ev nil, "(unless true :ran)"
    assert_ev "doc'd", '(defmacro m "docstring" [] "doc\'d") (m)'
    assert_ev :two, "(defmacro multi ([] :zero) ([a] :one) ([a b] :two)) (multi 1 2)"
  end

  def test_implicit_form_and_env
    ev("(defmacro the-form [& args] (list 'quote &form))")
    assert_ev List[sym("the-form"), 1, 2], "(the-form 1 2)"
    ev("(defmacro locals [] (list 'quote (vec (keys &env))))")
    assert_ev Vector[sym("a"), sym("b")], "(let [a 1 b 2] (locals))"
  end

  def test_macroexpand
    assert_ev List[sym("if"), sym("a"), List[sym("do"), sym("b")]], "(macroexpand-1 '(when a b))"
    assert_ev List[sym("f"), 1], "(macroexpand '(f 1))"
    assert_ev List[sym("if"), sym("x"), nil, List[sym("do"), 1]], "(macroexpand '(when-not x 1))"
  end

  def test_locals_shadow_macros
    assert_ev 3, "(let [when (fn [a b] (+ a b))] (when 1 2))"
  end

  def test_macros_are_not_values
    error = assert_raises(CompilerError) { ev("when") }
    assert_includes error.message, "Can't take value of a macro: #'clojure.core/when"
  end

  def test_macro_errors_are_compiler_errors
    error = assert_raises(CompilerError) { ev("(cond 1)") }
    assert_includes error.message, "cond requires an even number of forms"
    assert_raises(CompilerError) { ev("(let [a] a)") }
    assert_raises(CompilerError) { ev("(let (a 1) a)") }
  end

  def test_defn
    assert_ev 3, "(defn add [a b] (+ a b)) (add 1 2)"
    assert_ev :one, '(defn g "docstring" {:meta true} ([] :zero) ([a] :one)) (g 1)'
    error = assert_raises(ArityError) { ev("(add 1)") }
    assert_includes error.message, "user/add"
    assert_ev 120, "(defn fact [n] (if (<= n 1) 1 (* n (fact (dec n))))) (fact 5)"
  end

  def test_vector_destructuring
    assert_ev Vector[1, 2, List[3, 4], Vector[1, 2, 3, 4]],
              "(let [[a b & more :as all] [1 2 3 4]] [a b more all])"
    assert_ev Vector[1, nil], "(let [[a b] [1]] [a b])"
    assert_ev Vector[1, 2, 3], "(let [[a [b c]] [1 [2 3]]] [a b c])"
    assert_ev Vector[1, nil], "(let [[a & more] '(1)] [a more])"
  end

  def test_map_destructuring
    assert_ev Vector[1, 9, Map[{ x: 1 }]], "(let [{:keys [x y] :or {y 9} :as m} {:x 1}] [x y m])"
    assert_ev Vector[1, 2], "(let [{a :a b :b} {:a 1 :b 2}] [a b])"
    assert_ev Vector[1, 2], '(let [{:strs [a] :syms [b]} {"a" 1 (quote b) 2}] [a b])'
    assert_ev 3, "(let [{:keys [ns/x]} {:ns/x 3}] x)"
    assert_ev Vector[1, 2], "(let [{[a b] :pair} {:pair [1 2]}] [a b])"
    assert_ev 5, "(defn kw [& {:keys [n]}] n) (kw :n 5)"
  end

  def test_fn_and_loop_destructuring
    assert_ev Vector[1, 2], "((fn [{:keys [a]} [b]] [a b]) {:a 1} [2])"
    assert_ev 6, "(loop [[x & xs] [1 2 3] acc 0] (if x (recur xs (+ acc x)) acc))"
    assert_ev 120, "((fn fact [n] (if (<= n 1) 1 (* n (fact (dec n))))) 5)"
  end

  def test_control_flow_macros
    assert_ev nil, "(when false 1)"
    assert_ev 1, "(when-not false 1)"
    assert_ev :b, "(if-not true :a :b)"
    assert_ev nil, "(and 1 nil 2)"
    assert_ev true, "(and)"
    assert_ev 7, "(or nil false 7)"
    assert_ev nil, "(or)"
    assert_ev 3, "(cond false 1 nil 2 :else 3)"
    assert_ev nil, "(cond false 1)"
    assert_ev 19, "(-> 1 inc (* 10) (- 1))"
    assert_ev 94, "(->> [1 2 3] (reduce +) (- 100))"
    assert_ev nil, "(comment (this is ignored))"
    assert_ev 2, "(if-let [[a b] [1 2]] b :no)"
    assert_ev :no, "(if-let [a nil] a :no)"
    assert_ev 1, "(when-let [a 1] a)"
    assert_ev false, "(if-some [a false] a :no)"
    assert_ev nil, "(when-some [a nil] a)"
  end

  def test_case_and_condp
    assert_ev :two, "(case 2 1 :one (2 3) :two :default)"
    assert_ev :sym, "(case 'x x :sym :other)"
    assert_ev :default, "(case 9 1 :one :default)"
    error = assert_raises(ExceptionInfo) { ev("(case :zz :a 1)") }
    assert_equal "No matching clause: :zz", error.message
    assert_ev :three, "(condp = 3 1 :one 3 :three :none)"
    assert_ev :none, "(condp = 5 1 :one :none)"
  end

  def test_looping_macros
    assert_ev Vector[Vector[1, :a], Vector[1, :b], Vector[3, :a], Vector[3, :b]],
              "(def a (atom [])) (doseq [x [1 2 3] :when (odd? x) y [:a :b]] (swap! a conj [x y])) @a"
    assert_ev Vector[2, 4], "(def b (atom [])) (doseq [x [1 2] :let [y (* 2 x)]] (swap! b conj y)) @b"
    assert_ev nil, "(doseq [x [1]] x)"
    assert_output("012") { ev("(dotimes [i 3] (print i))") }
    assert_ev 3, "(def c (atom 0)) (while (< @c 3) (swap! c inc)) @c"
    assert_raises(CompilerError) { ev("(doseq [x [1] :while true] x)") }
  end

  def test_declare_and_assert
    assert_ev 1, "(declare later) (defn uses-later [] (later)) (defn later [] 1) (uses-later)"
    assert_ev nil, "(assert true)"
    error = assert_raises(ExceptionInfo) { ev('(assert (= 1 2) "math")') }
    assert_equal "Assert failed: math\n(= 1 2)", error.message
  end

  def test_sequence_functions
    assert_ev 2, "(second [1 2 3])"
    assert_ev 3, "(last [1 2 3])"
    assert_ev List[1, 2], "(butlast [1 2 3])"
    assert_ev List[3, 2, 1], "(reverse [1 2 3])"
    assert_ev Vector[1, 2, 3], "(into [1] '(2 3))"
    assert_ev Map[{ a: 1 }], "(into {} [[:a 1]])"
    assert_ev List[3], "(nthnext [1 2 3] 2)"
    assert_ev List[1, 2, 3], "(list* 1 [2 3])"
    assert_ev true, "(every? odd? [1 3])"
    assert_ev true, "(some even? [1 2])"
    assert_ev nil, "(some even? [1 3])"
    assert_ev true, "(not-any? even? [1 3])"
    assert_ev nil, "(not-empty [])"
    assert_ev Map[{ a: 2, b: 1 }], "(frequencies [:a :b :a])"
    assert_ev Map[{ true => Vector[1, 3], false => Vector[2] }], "(group-by odd? [1 2 3])"
    assert_ev List[1, :x, 2], "(interpose :x [1 2])"
  end

  def test_function_combinators
    assert_ev 11, "((comp inc (partial * 2)) 5)"
    assert_ev 4, "((comp inc inc inc) 1)"
    assert_ev false, "((complement odd?) 1)"
    assert_ev 7, "((constantly 7) 1 2 3)"
    assert_ev Vector[2, 0], "((juxt inc dec) 1)"
    assert_ev 1, "((fnil inc 0) nil)"
    assert_ev 5, "(identity 5)"
  end

  def test_map_functions
    assert_ev Map[{ a: 1, b: 3 }], "(merge {:a 1 :b 2} nil {:b 3})"
    assert_ev nil, "(merge nil nil)"
    assert_ev Map[{ a: 3 }], "(merge-with + {:a 1} {:a 2})"
    assert_ev Map[{ a: 1 }], "(select-keys {:a 1 :b 2} [:a :z])"
    assert_ev Map[{ a: 1, b: 2 }], "(zipmap [:a :b :c] [1 2])"
    assert_ev 1, "(get-in {:a {:b 1}} [:a :b])"
    assert_ev :nf, "(get-in {:a {}} [:a :b] :nf)"
    assert_ev Map[{ a: 2 }], "(update {:a 1} :a inc)"
    assert_ev Map[{ a: Map[{ b: 1 }] }], "(assoc-in {} [:a :b] 1)"
    assert_ev Map[{ a: Map[{ b: 11 }] }], "(update-in {:a {:b 1}} [:a :b] + 10)"
  end
end
