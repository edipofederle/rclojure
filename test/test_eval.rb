require "test_helper"

class TestEval < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def assert_compile_error(message, source)
    error = assert_raises(CompilerError) { ev(source) }
    assert_includes error.message, message
  end

  def test_self_evaluating
    assert_ev 1, "1"
    assert_ev "s", '"s"'
    assert_ev :k, ":k"
    assert_ev nil, "nil"
    assert_ev List::EMPTY, "()"
  end

  def test_collection_literals_evaluate_elements
    assert_ev Vector[3, :a], "[(+ 1 2) :a]"
    assert_ev Map[{ a: 2 }], "{:a (+ 1 1)}"
    assert_ev Set[1, 2], "\#{1 (+ 1 1)}"
  end

  def test_quote
    assert_ev List[Symbol.parse("+"), 1, 2], "'(+ 1 2)"
    assert_ev Symbol.parse("x"), "(quote x)"
  end

  def test_arithmetic
    assert_ev 6, "(+ 1 2 3)"
    assert_ev 0, "(+)"
    assert_ev(-5, "(- 5)")
    assert_ev 24, "(* 2 3 4)"
    assert_ev Rational(1, 3), "(/ 1 3)"
    assert_ev 2, "(/ 4 2)"
    assert_ev 0.5, "(/ 1.0 2)"
    assert_ev 1, "(+ 1/2 1/2)"
    assert_raises(ZeroDivisionError) { ev("(/ 1 0)") }
  end

  def test_comparison_and_equality
    assert_ev true, "(< 1 2 3)"
    assert_ev false, "(< 1 3 2)"
    assert_ev true, "(>= 3 3 1)"
    assert_ev true, "(= [1 2] '(1 2))"
    assert_ev false, "(= 1 1.0)"
    assert_ev true, "(not= 1 2)"
  end

  def test_def_and_var
    assert_equal "#'user/x", RClojure.pr_str(ev("(def x 10)"))
    assert_ev 10, "x"
    assert_ev 10, "user/x"
    ev("(def x 20)")
    assert_ev 20, "x"
    assert_ev 3, '(def y "docstring" 3) y'
    assert_kind_of Var, ev("(var x)")
    assert_raises(Error) { ev("(def unbound) unbound") }
  end

  def test_def_shadows_core
    assert_ev 42, "(def + (fn* [a b] 42)) (+ 1 2)"
    assert_ev 3, "(clojure.core/+ 1 2)"
  end

  def test_if_truthiness
    assert_ev :t, "(if 0 :t :f)"
    assert_ev :t, '(if "" :t :f)'
    assert_ev :t, "(if [] :t :f)"
    assert_ev :f, "(if nil :t :f)"
    assert_ev :f, "(if false :t :f)"
    assert_ev nil, "(if false :t)"
  end

  def test_do
    assert_ev 3, "(do 1 2 3)"
    assert_ev nil, "(do)"
    assert_ev 2, "(do (def a 2) a)"
  end

  def test_let
    assert_ev 3, "(let* [a 1 b (+ a 1)] (+ a b))"
    assert_ev 2, "(let* [x 1 x (+ x 1)] x)"
    assert_ev 1, "(let* [x 1] (let* [x 2] x) x)"
    assert_ev nil, "(let* [])"
  end

  def test_loop_recur
    assert_ev 4_999_950_000, "(loop* [i 0 acc 0] (if (< i 100000) (recur (+ i 1) (+ acc i)) acc))"
    assert_ev :done, "(loop* [] :done)"
  end

  def test_closures_capture_each_iteration
    fns = ev("(loop* [i 0 fs []] (if (< i 3) (recur (+ i 1) [(fn* [] i) fs]) fs))")
    values = []
    while fns.size == 2
      values << fns[0].call
      fns = fns[1]
    end
    assert_equal [2, 1, 0], values
  end

  def test_fn
    assert_ev 3, "((fn* [a b] (+ a b)) 1 2)"
    assert_ev nil, "((fn* []))"
    assert_ev 11, "(let* [n 10] ((fn* [x] (+ x n)) 1))"
  end

  def test_fn_multi_arity_and_variadic
    ev("(def f (fn* ([] :zero) ([a] :one) ([a b & more] more)))")
    assert_ev :zero, "(f)"
    assert_ev :one, "(f 1)"
    assert_ev nil, "(f 1 2)"
    assert_ev List[3, 4], "(f 1 2 3 4)"
  end

  def test_named_fn_recursion
    assert_ev 3_628_800, "((fn* fact [n] (if (<= n 1) 1 (* n (fact (- n 1))))) 10)"
    assert_ev 120, "(def fact (fn* [n] (if (<= n 1) 1 (* n (fact (- n 1)))))) (fact 5)"
  end

  def test_recur_in_fn
    assert_ev :done, "((fn* [n] (if (= n 0) :done (recur (- n 1)))) 100000)"
    assert_ev 6, "((fn* [acc & xs] (if xs (recur (+ acc 1) nil) acc)) 5 :a :b)"
  end

  def test_arity_errors
    error = assert_raises(ArityError) { ev("((fn* f [a] a))") }
    assert_equal "Wrong number of args (0) passed to: f", error.message
    assert_raises(ArityError) { ev("(-)") }
  end

  def test_recur_validation
    assert_compile_error "Can only recur from tail position", "(loop* [x 1] (+ 1 (recur 2)))"
    assert_compile_error "Can only recur from tail position", "(recur 1)"
    assert_compile_error "Can only recur from tail position", "(loop* [x (recur 1)] x)"
    assert_compile_error "Mismatched argument count to recur, expected: 1 args, got: 2",
                         "(loop* [x 1] (recur 1 2))"
    assert_compile_error "Cannot recur across try", "(loop* [x 1] (try (recur 2)))"
  end

  def test_compile_errors
    assert_compile_error "Unable to resolve symbol: nope", "(nope)"
    assert_compile_error "Unable to resolve symbol: if", "if"
    assert_compile_error "Too few arguments to if", "(if 1)"
    assert_compile_error "Too many arguments to if", "(if 1 2 3 4)"
    assert_compile_error "Too many arguments to def", "(def a 1 2 3)"
    assert_compile_error "even number of forms", "(let* [a] a)"
    assert_compile_error "Bad binding form", "(let* [:a 1] 1)"
    assert_compile_error "Can't have 2 overloads with same arity", "(fn* ([a] 1) ([b] 2))"
    assert_compile_error "Can't have more than 1 variadic overload", "(fn* ([& a] 1) ([b & c] 2))"
    assert_compile_error "more params than variadic", "(fn* ([a b] 1) ([a & c] 2))"
    assert_compile_error "& must be followed by exactly one symbol", "(fn* [a &] 1)"
  end

  def test_try_catch_finally
    assert_ev Map[{ a: 1 }], '(try (throw (ex-info "boom" {:a 1})) (catch ExceptionInfo e (ex-data e)))'
    assert_ev "divided by 0", "(try (/ 1 0) (catch ZeroDivisionError e (ex-message e)))"
    assert_ev :caught, "(try (/ 1 0) (catch ArgumentError e :wrong) (catch :default e :caught))"
    assert_ev 1, "(try 1 (finally 2))"
    assert_ev :ran, "(def log nil) (try 1 (finally (def log :ran))) log"
    assert_ev :ran, "(def log nil) (try (try (/ 1 0) (finally (def log :ran))) (catch :default e log))"
    assert_raises(ZeroDivisionError) { ev("(try (/ 1 0) (catch ExceptionInfo e :nope))") }
    assert_compile_error "Unable to resolve classname: NotAClass", "(try 1 (catch NotAClass e 2))"
  end

  def test_throw
    error = assert_raises(ExceptionInfo) { ev('(throw (ex-info "bad" {:code 7}))') }
    assert_equal "bad", error.message
    assert_equal Map[{ code: 7 }], error.data
    assert_raises(Error) { ev("(throw 42)") }
  end

  def test_collections_and_keywords_are_callable
    assert_ev 1, "(:a {:a 1})"
    assert_ev :none, "(:b {:a 1} :none)"
    assert_ev nil, "(:a nil)"
    assert_ev 2, "({:a 2} :a)"
    assert_ev :y, "([:x :y] 1)"
    assert_raises(IndexError) { ev("([:x] 5)") }
    assert_ev :x, '(#{:x} :x)'
    assert_raises(Error) { ev("(1 2)") }
  end
end
