require "test_helper"

class TestInterop < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def test_instance_method_calls
    assert_ev "HELLO", '(.upcase "hello")'
    assert_ev "***hi***", '(.center "hi" 8 "*")'
    assert_ev true, '(.empty? "")'
    assert_ev 16, "(.reduce [1 2 3] 10 :+)"
  end

  def test_dot_special_form
    assert_ev "HELLO", '(. "hello" upcase)'
    assert_ev "***hello***", '(. "hello" (center 11 "*"))'
  end

  def test_kebab_case_method_names
    assert_ev true, '(.start-with? "rclojure" "rc")'
    assert_ev Rational(1, 2), "(.to-r 0.5)"
  end

  def test_class_method_calls_and_constants
    assert_ev 4.0, "(Math/sqrt 16)"
    assert_ev Math::PI, "Math/PI"
    assert_ev 1970, "(.year (.utc (Time/at 0)))"
    assert_ev String, "String"
    assert_ev File::Stat, "File::Stat"
    assert_ev RUBY_VERSION, "RUBY_VERSION"
  end

  def test_ruby_values_work_with_seq_functions
    assert_ev 3, '(count (.split "a,b,c" ","))'
    assert_ev "a", '(first (.split "a,b,c" ","))'
    assert_ev Vector[:a, 1], "(first (.to-h {:a 1}))"
  end

  def test_threading_through_ruby_methods
    assert_equal %w[SOME TEXT], ev('(-> "  some text  " .strip .upcase (.split " "))')
  end

  def test_macroexpansion_of_shorthands
    assert_ev ev("'(. bar foo 1)"), "(macroexpand-1 '(.foo bar 1))"
    assert_ev ev("'(. Math sqrt 4)"), "(macroexpand-1 '(Math/sqrt 4))"
  end

  def test_syntax_quote_leaves_ruby_names_alone
    assert_ev ev("'(String Math/sqrt .foo)"), "`(String Math/sqrt .foo)"
  end

  def test_rclojure_namespaces_win_over_ruby_constants
    assert_ev 3, "(clojure.core/+ 1 2)"
  end

  def test_strings_stay_immutable
    assert_raises(FrozenError) { ev('(.upcase! "abc")') }
  end

  def test_errors
    assert_raises(NoMethodError) { ev("(.nope 1)") }
    assert_raises(CompilerError) { ev("(Nope/thing)") }
    assert_raises(CompilerError) { ev("(.upcase)") }
    assert_raises(CompilerError) { ev("(. 1)") }
    assert_raises(CompilerError) { ev("lowercase-unknown") }
  end

  def test_blocks
    assert_equal [2, 3, 4], ev("(.map [1 2 3] & inc)")
    assert_equal [0, 1, 4], ev("(Array/new 3 & (fn [i] (* i i)))")
    assert_equal 6, ev("(.reduce [1 2 3] & +)")
    assert_equal [[:a, 0], [:b, 1]], ev("(.map (.each-with-index [:a :b]) & (fn [x i] [x i]))").map(&:to_a)
    assert_equal [1], ev("(.each-with-object {:a 1} (Array/new) & (fn [[k v] acc] (.push acc v)))")
    assert_equal [2, 4], ev("(. [1 2] (map & (fn [x] (* 2 x))))")
  end

  def test_block_values_convert_like_rubys_ampersand
    assert_equal %w[A B], ev('(.map ["a" "b"] & :upcase)')
    assert_equal [1, 2], ev("(.map [:a :b] & {:a 1 :b 2})")
    assert_equal [:x, nil], ev('(.map [:x :y] & #{:x})')
    assert_equal [2, 4], [1, 2].map(&ev("(fn [x] (* 2 x))"))
  end

  def test_block_errors
    assert_raises(CompilerError) { ev("(.map [1] & inc 2)") }
    assert_raises(CompilerError) { ev("(.map [1] &)") }
    assert_raises(ArityError) { ev("(.each-with-index [1] & (fn [x] x))") }
  end

  def test_constructors
    assert_ev "abc", '(String. "abc")'
    assert_ev "x", '(new String "x")'
    assert_ev (1..3), "(Range. 1 3)"
    assert_equal [0, 1], ev("(Array. 2 & (fn [i] i))")
    assert_ev true, '(instance? File::Stat (File::Stat. "."))'
    assert_ev ev("'(new String \"x\")"), '(macroexpand-1 \'(String. "x"))'
    assert_raises(CompilerError) { ev("(new Nope)") }
    assert_raises(CompilerError) { ev("(Math. 1)") }
    assert_raises(CompilerError) { ev("(new (identity String))") }
  end

  def test_double_dot_and_doto
    assert_ev "**HELLO**", '(.. "hello" upcase (center 9 "*"))'
    assert_ev 1970, "(.. Time (at 0) utc year)"
    assert_equal [1, 2], ev("(doto (Array/new) (.push 1) (.push 2))")
    assert_equal({ a: 1 }, ev("(doto (Hash/new) (.store :a 1))"))
  end

  def test_attributes_and_set!
    ev "(def Point (Struct/new :x))"
    ev "(def p (.new Point 1))"
    assert_ev 1, "(.-x p)"
    assert_ev 5, "(set! (.-x p) 5)"
    assert_ev 5, "(.x p)"
    assert_ev 6, "(do (set! (.x p) 6) (.-x p))"
    assert_ev 7, "(do (set! (. p x) 7) (. p -x))"
    assert_ev 8, "(do (set! (. p -x) 8) (.-x p))"
    assert_raises(CompilerError) { ev("(.-x p 1)") }
    assert_raises(CompilerError) { ev("(let [y 1] (set! y 2))") }
    # set! on a var needs a thread binding (see test_dynamic_vars)
    assert_equal "Can't change/establish root binding of: p with set", assert_raises(Error) { ev("(set! p 2)") }.message
    assert_raises(CompilerError) { ev("(set! (.x p 1) 2)") }
    assert_raises(CompilerError) { ev("(set! 1 2)") }
  end

  def test_instance_and_class
    assert_ev true, '(instance? String "a")'
    assert_ev false, "(instance? Integer 1.0)"
    assert_ev true, "(instance? Comparable 1)"
    assert_ev String, '(class "a")'
    assert_ev nil, "(class nil)"
    assert_ev nil, "(type nil)"
  end

  def test_converting_collections
    assert_equal({ a: [1, 2], "b" => [3] }, ev("(clj->rb {:a [1 2] 'b \#{3}})"))
    assert_equal [2, 3], ev("(clj->rb (map inc [1 2]))")
    assert_nil ev("(clj->rb nil)")
    assert_ev Vector[1, 2, 3], "(rb->clj (.to-a (Range/new 1 3)))"
    assert_ev Set[1, 2], "(rb->clj (Set/new [1 2]))"
    assert_ev true, "(= {:a [1 {:b 2}]} (rb->clj (clj->rb {:a [1 {:b 2}]})))"
    assert_ev Map[{ a: Vector[1] }], "(rb->clj {:a (Array/new 1 1)})"
  end

  def test_ruby_enumerables_are_seqable
    assert_ev List[1, 2, 3], "(seq (Range/new 1 3))"
    assert_ev nil, "(seq (Range/new 1 0))"
    assert_ev List[1, 2, 3], "(take 3 (Range/new 1 nil))"
    assert_ev List[2, 3], "(map inc (Range/new 1 2))"
    assert_ev "a", '(first (.each-char "abc"))'
    assert_ev List[1, 2], "(seq (Set/new [1 2]))"
  end

  # As Clojure's get and contains? work on java.util.Map, Set and arrays.
  def test_get_and_contains_on_ruby_collections
    assert_ev Vector[1, :nf, true, false], "(let [h (clj->rb {:a 1})] [(get h :a) (get h :b :nf) (contains? h :a) (contains? h :b)])"
    assert_ev Vector[2, nil, true, false], "(let [a (clj->rb [1 2])] [(get a 1) (get a 2) (contains? a 1) (contains? a 2)])"
    assert_ev Vector[1, nil, true], "(let [s (Set/new (clj->rb [1]))] [(get s 1) (get s 2) (contains? s 1)])"
    assert_ev 1, "(:a (clj->rb {:a 1}))"
  end

  class Greeting
    def to_s = "hello"
    def inspect = "#<Greeting>"
  end

  def test_str_of_ruby_objects_uses_to_s
    require "date"
    assert_ev "2026-11-22", "(str (Date/new 2026 11 22))"
    assert_ev "1970-01-01 00:00:00 UTC", "(str (.utc (Time/at 0)))"
    assert_ev "hello!", '(str (TestInterop::Greeting/new) "!")'
    assert_ev "[#<Greeting>]", "(str [(TestInterop::Greeting/new)])"
    assert_ev "#<Greeting>", "(pr-str (TestInterop::Greeting/new))"
    assert_ev "[1 \"a\"]:k", '(str [1 "a"] :k)'
  end
end
