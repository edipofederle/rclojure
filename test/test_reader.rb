require "test_helper"

class TestReader < Minitest::Test
  include RClojureTestHelpers
  include RClojure

  def test_constants
    assert_nil read("nil")
    assert_equal true, read("true")
    assert_equal false, read("false")
  end

  def test_numbers
    assert_equal 42, read("42")
    assert_equal(-7, read("-7"))
    assert_equal 7, read("+7")
    assert_equal 10**30, read("1000000000000000000000000000000N")
    assert_equal 3.5, read("3.5")
    assert_equal 1.5e3, read("1.5e3")
    assert_equal Rational(1, 2), read("1/2")
    assert_raises(ReaderError) { read("12abc") }
  end

  def test_strings
    assert_equal "hello", read('"hello"')
    assert_equal "a\nb\t\"c\"\\", read('"a\nb\t\"c\"\\\\"')
    assert_equal "é", read('"é"')
    assert read('"x"').frozen?
    assert_raises(EOFError) { read('"open') }
  end

  def test_symbols_and_keywords
    assert_equal sym("foo"), read("foo")
    assert_equal Symbol.new("clojure.core", "map"), read("clojure.core/map")
    assert_equal sym("/"), read("/")
    assert_equal sym("+"), read("+")
    assert_equal sym("-"), read("-")
    assert_equal sym("empty?"), read("empty?")
    assert_equal :foo, read(":foo")
    assert_equal :"ns/foo", read(":ns/foo")
  end

  def test_collections
    assert_equal List[1, 2, List[3]], read("(1 2 (3))")
    assert_equal List::EMPTY, read("()")
    assert_equal Vector[1, sym("a"), :b], read("[1 a :b]")
    assert_equal Map[{ a: 1, "b" => Vector[2] }], read('{:a 1, "b" [2]}')
    assert_equal Set[1, 2, 3], read("#\{3 2 1}")
  end

  def test_reader_macros
    assert_equal List[sym("quote"), sym("x")], read("'x")
    assert_equal List[sym("syntax-quote"), List[sym("a"), List[sym("unquote"), sym("b")],
                                                List[sym("unquote-splicing"), sym("c")]]],
                 read("`(a ~b ~@c)")
    assert_equal List[sym("deref"), sym("atom")], read("@atom")
  end

  def test_comments_whitespace_and_discard
    assert_equal Vector[1, 3], read("[1 ; one\n ,, #_2 3]")
    assert_equal 5, read("#_ #_ 1 2 5")
  end

  def test_read_all
    assert_equal [1, sym("a"), Vector[]], Reader.read_all("1 a ; trailing\n []")
  end

  def test_errors
    assert_raises(EOFError) { read("(1 2") }
    assert_raises(EOFError) { read("") }
    assert_raises(ReaderError) { read(")") }
    assert_raises(ReaderError) { read("{:a}") }
    assert_raises(ReaderError) { read("{:a 1 :a 2}") }
    assert_raises(ReaderError) { read("#\{1 1}") }
    assert_raises(ReaderError) { read("1 2") }

    error = assert_raises(ReaderError) { read("(1\n  ]") }
    assert_equal 2, error.line
    assert_equal 3, error.column
  end
end
