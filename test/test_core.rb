require "test_helper"

class TestCore < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def test_equality_is_numeric_category_aware_all_the_way_down
    assert_ev false, "(= [1] [1.0])"
    assert_ev false, "(= {:a 1} {:a 1.0})"
    assert_ev true, "(= {:a [1 2]} {:a '(1 2)})"
    assert_ev true, "(= 1 1 1)"
    assert_ev true, "(== 1 1.0)"
    assert_ev true, "(= \#{1 2} \#{2 1})"
  end

  def test_numbers
    assert_ev 2, "(inc 1)"
    assert_ev 0, "(dec 1)"
    assert_ev(-3, "(quot -7 2)")
    assert_ev(-1, "(rem -7 2)")
    assert_ev 1, "(mod -7 2)"
    assert_ev 9, "(max 3 9 4)"
    assert_ev 3, "(min 3 9 4)"
    assert_ev 5, "(abs -5)"
    assert_ev true, "(even? 4)"
    assert_ev true, "(odd? -3)"
    assert_ev true, "(zero? 0)"
    assert_ev true, "(pos? 1/2)"
    assert_ev true, "(neg? -0.5)"
    assert_ev true, "(ratio? 1/2)"
    assert_ev true, "(rational? 3)"
    assert_ev false, "(integer? 1.0)"
    assert_raises(ArgumentError) { ev("(even? 1.5)") }
    assert_raises(ZeroDivisionError) { ev("(quot 1 0)") }
  end

  def test_constructors
    assert_ev List[1, 2], "(list 1 2)"
    assert_ev Vector[1, 2], "(vector 1 2)"
    assert_ev Map[{ a: 1 }], "(hash-map :a 1)"
    assert_ev Set[1], "(hash-set 1 1)"
    assert_ev Vector[1, 2], "(vec '(1 2))"
    assert_ev Set[1, 2], "(set [1 2 1])"
    assert_raises(ArgumentError) { ev("(hash-map :a)") }
  end

  def test_seq_functions
    assert_ev nil, "(seq [])"
    assert_ev nil, "(seq nil)"
    assert_ev List[1, 2], "(seq [1 2])"
    assert_ev List[Vector[:a, 1]], "(seq {:a 1})"
    assert_ev 1, "(first [1 2])"
    assert_ev nil, "(first nil)"
    assert_ev List[2], "(rest [1 2])"
    assert_ev List::EMPTY, "(rest nil)"
    assert_ev nil, "(next [1])"
    assert_ev List[2], "(next [1 2])"
    assert_ev List[0, 1], "(cons 0 [1])"
    assert_ev Vector[:a, 1], "(first {:a 1})"
  end

  def test_conj
    assert_ev Vector[1, 2, 3], "(conj [1] 2 3)"
    assert_ev List[3, 2, 1], "(conj '(1) 2 3)"
    assert_ev List[1], "(conj nil 1)"
    assert_ev Set[1, 2], "(conj \#{1} 2 1)"
    assert_ev Map[{ a: 1, b: 2, c: 3 }], "(conj {:a 1} [:b 2] {:c 3})"
    assert_ev Vector[], "(conj)"
    assert_raises(ArgumentError) { ev("(conj {} [1 2 3])") }
  end

  def test_counting_and_indexing
    assert_ev 3, "(count [1 2 3])"
    assert_ev 0, "(count nil)"
    assert_ev 2, "(count {:a 1 :b 2})"
    assert_ev 3, '(count "abc")'
    assert_ev true, "(empty? [])"
    assert_ev true, "(empty? nil)"
    assert_ev false, "(empty? {:a 1})"
    assert_ev :b, "(nth [:a :b] 1)"
    assert_ev :b, "(nth '(:a :b) 1)"
    assert_ev :none, "(nth [] 5 :none)"
    assert_raises(IndexError) { ev("(nth [] 0)") }
    assert_ev 3, "(peek [1 2 3])"
    assert_ev 1, "(peek '(1 2 3))"
    assert_ev Vector[1, 2], "(pop [1 2 3])"
    assert_ev List[2, 3], "(pop '(1 2 3))"
    assert_raises(Error) { ev("(pop [])") }
  end

  def test_associative_functions
    assert_ev 1, "(get {:a 1} :a)"
    assert_ev :d, "(get {:a 1} :b :d)"
    assert_ev :x, "(get [:x] 0)"
    assert_ev nil, "(get nil :a)"
    assert_ev Map[{ a: 1, b: 2 }], "(assoc {:a 1} :b 2)"
    assert_ev Map[{ a: 1 }], "(assoc nil :a 1)"
    assert_ev Vector[:x, :z], "(assoc [:x :y] 1 :z)"
    assert_ev Vector[:x, :y], "(assoc [:x] 1 :y)"
    assert_raises(IndexError) { ev("(assoc [] 5 :y)") }
    assert_ev Map[{ b: 2 }], "(dissoc {:a 1 :b 2 :c 3} :a :c)"
    assert_ev Set[2], "(disj \#{1 2} 1)"
    assert_ev true, "(contains? {:a nil} :a)"
    assert_ev true, "(contains? [:x] 0)"
    assert_ev false, "(contains? \#{1} 2)"
    assert_ev List[:a, :b], "(keys {:a 1 :b 2})"
    assert_ev List[1, 2], "(vals {:a 1 :b 2})"
    assert_ev nil, "(keys {})"
    assert_ev :a, "(key (first {:a 1}))"
    assert_ev 1, "(val (first {:a 1}))"
  end

  def test_reduce_and_apply
    assert_ev 6, "(reduce + [1 2 3])"
    assert_ev 16, "(reduce + 10 [1 2 3])"
    assert_ev 0, "(reduce + [])"
    assert_ev 7, "(reduce + [7])"
    assert_ev 10, "(apply + 1 2 [3 4])"
    assert_ev 0, "(apply + [])"
  end

  def test_collection_predicates
    assert_ev true, "(coll? {})"
    assert_ev false, "(coll? \"s\")"
    assert_ev true, "(seq? '(1))"
    assert_ev false, "(seq? [1])"
    assert_ev true, "(sequential? [1])"
    assert_ev true, "(vector? [])"
    assert_ev true, "(map? {})"
    assert_ev true, "(set? \#{})"
    assert_ev true, "(list? ())"
  end

  def test_strings_symbols_keywords
    assert_ev "a1:k[1 \"s\"]", '(str "a" 1 nil :k [1 "s"])'
    assert_ev "", "(str)"
    assert_ev "ell", '(subs "hello" 1 4)'
    assert_ev "llo", '(subs "hello" 2)'
    assert_raises(IndexError) { ev('(subs "hi" 3)') }
    assert_ev "foo", "(name :ns/foo)"
    assert_ev "ns", "(namespace :ns/foo)"
    assert_ev nil, "(namespace :foo)"
    assert_ev "bar", "(name 'a.b/bar)"
    assert_ev :foo, '(keyword "foo")'
    assert_ev :"ns/foo", '(keyword "ns" "foo")'
    assert_ev Symbol.new("ns", "x"), '(symbol "ns/x")'
    assert_ev Symbol.new(nil, "k"), "(symbol :k)"
    assert_ev true, "(keyword? :a)"
    assert_ev true, "(symbol? 'a)"
    assert_ev true, '(string? "a")'
  end

  def test_printing
    assert_ev '"a" [1 "b"]', '(pr-str "a" [1 "b"])'
    assert_ev "a [1 b]", '(print-str "a" [1 "b"])'
    assert_output("hello [1 x] nil\n") { assert_nil ev('(println "hello" [1 "x"] nil)') }
    assert_output("\"hello\" :k\n") { ev('(prn "hello" :k)') }
    assert_output("ab") { ev('(print "a") (pr (symbol "b"))') }
  end

  def test_logic_and_identity
    assert_ev true, "(not nil)"
    assert_ev false, "(not 0)"
    assert_ev true, "(nil? nil)"
    assert_ev true, "(some? false)"
    assert_ev true, "(true? true)"
    assert_ev false, "(true? 1)"
    assert_ev true, "(false? false)"
    assert_ev false, "(boolean nil)"
    assert_ev true, "(fn? +)"
    assert_ev true, "(fn? (fn* []))"
    assert_ev false, "(fn? :k)"
    assert_ev true, "(let* [v [1]] (identical? v v))"
    assert_ev(-1, "(compare 1 2)")
    assert_ev(-1, "(compare nil 1)")
    assert_ev Integer, "(type 1)"
  end

  def test_atoms
    assert_ev 1, "(def a (atom 0)) (swap! a inc)"
    assert_ev 11, "(swap! a + 4 6)"
    assert_ev 11, "@a"
    assert_ev :reset, "(reset! a :reset)"
    assert_ev :reset, "(deref a)"
    assert_ev 5, "(def v 5) (deref (var v))"
  end

  def test_eval_and_read_string
    assert_ev List[Symbol.parse("+"), 1, 2], '(read-string "(+ 1 2)")'
    assert_ev 3, "(eval '(+ 1 2))"
    assert_ev 42, "(eval (read-string \"(def x 42)\")) x"
  end

  def test_exceptions
    assert_ev "boom", '(ex-message (ex-info "boom" {}))'
    assert_ev nil, "(ex-data 1)"
    assert_ev "inner", '(ex-message (ex-cause (ex-info "outer" {} (ex-info "inner" {}))))'
  end
end
