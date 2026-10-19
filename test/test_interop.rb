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
end
