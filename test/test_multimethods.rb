require "test_helper"

class TestMultimethods < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def setup
    super
    ev <<~CLJ
      (defmulti area "Area of a shape." :shape)
      (defmethod area :rect [{:keys [w h]}] (* w h))
      (defmethod area :circle [{:keys [r]}] (* 3 r r))
    CLJ
  end

  def test_dispatch
    assert_ev List[6, 3], "(map area [{:shape :rect :w 2 :h 3} {:shape :circle :r 1}])"
    assert_ev "Area of a shape.", "(:doc (meta #'area))"
    assert_ev "#<multifn area>", "(pr-str area)"
    assert_ev true, "(instance? RClojure::MultiFn area)"
  end

  def test_missing_methods_and_defaults
    error = assert_raises(ArgumentError) { ev("(area {:shape :tri})") }
    assert_equal "No method in multimethod 'area' for dispatch value: :tri", error.message
    assert_ev :unknown, "(defmethod area :default [_] :unknown) (area {:shape :tri})"
    assert_ev :other, "(defmulti m identity :default :other) (defmethod m :other [_] :other) (m 1)"
  end

  def test_method_tables
    assert_ev 2, "(count (methods area))"
    assert_ev true, "(fn? (get-method area :rect))"
    assert_ev nil, "(get-method area :tri)"
    assert_ev 1, "(remove-method area :rect) (count (methods area))"
    assert_ev 0, "(remove-all-methods area) (count (methods area))"
  end

  def test_defmulti_again_keeps_methods
    assert_ev 12, "(defmulti area :other) (area {:shape :circle :r 2})"
  end

  def test_hierarchy_dispatch_and_preferences
    ev <<~CLJ
      (derive ::square ::rect)
      (derive ::rect ::shape)
      (defmulti describe :kind)
      (defmethod describe ::shape [_] "a shape")
      (defmethod describe ::rect [_] "a rect")
    CLJ
    assert_ev Vector["a rect", "a shape"], "[(describe {:kind ::square}) (describe {:kind ::shape})]"

    ev "(derive ::square ::equal-sided) (defmethod describe ::equal-sided [_] \"equal sided\")"
    error = assert_raises(ArgumentError) { ev("(describe {:kind ::square})") }
    assert_equal "Multiple methods in multimethod 'describe' match dispatch value: :user/square -> " \
                 ":user/equal-sided and :user/rect, and neither is preferred", error.message
    assert_ev "a rect", "(prefer-method describe ::rect ::equal-sided) (describe {:kind ::square})"
    assert_ev Map[{ "user/rect": Set[:"user/equal-sided"] }], "(prefers describe)"
    error = assert_raises(Error) { ev("(prefer-method describe ::equal-sided ::rect)") }
    assert_match "Preference conflict in multimethod 'describe'", error.message
  end

  def test_cache_follows_the_hierarchy
    ev "(defmulti kind :kind :default :none) (defmethod kind :none [_] :none) (defmethod kind ::base [_] :base)"
    assert_ev :none, "(kind {:kind ::late})"
    assert_ev :base, "(derive ::late ::base) (kind {:kind ::late})"
    assert_ev :none, "(underive ::late ::base) (kind {:kind ::late})"
  end

  def test_class_and_vector_dispatch
    ev <<~CLJ
      (defmulti kind class)
      (defmethod kind Numeric [_] :number)
      (defmethod kind Comparable [_] :comparable)
      (defmethod kind String [_] :string)
      (prefer-method kind Numeric Comparable)
      (defmulti pair (fn [a b] [(class a) (class b)]))
      (defmethod pair [Integer String] [a b] :int-str)
      (defmethod pair [Numeric Numeric] [a b] :nums)
    CLJ
    assert_ev Vector[:number, :number, :string, :comparable], "[(kind 1) (kind 1.5) (kind \"s\") (kind (Time/now))]"
    assert_ev Vector[:"int-str", :nums], "[(pair 1 \"a\") (pair 1 2.0)]"
  end

  def test_custom_hierarchies
    ev "(def h (-> (make-hierarchy) (derive :a :b) (derive :b :c)))"
    assert_ev true, "(isa? h :a :c)"
    assert_ev false, "(isa? (underive h :a :b) :a :c)"
    assert_ev :via_c, "(defmulti local-h identity :hierarchy #'h) (defmethod local-h :c [_] :via_c) (local-h :a)"
    # thrown while expanding the macro, so wrapped like Clojure's CompilerException
    assert_match "Only these options are valid", assert_raises(CompilerError) { ev("(defmulti bad identity :wrong 1)") }.message
  end
end

class TestHierarchies < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def test_derive_and_queries
    ev "(derive ::square ::rect) (derive ::rect ::shape)"
    assert_ev true, "(isa? ::square ::shape)"
    assert_ev false, "(isa? ::shape ::square)"
    assert_ev Set[:"user/rect"], "(parents ::square)"
    assert_ev Set[:"user/rect", :"user/shape"], "(ancestors ::square)"
    assert_ev Set[:"user/rect", :"user/square"], "(descendants ::shape)"
    assert_ev nil, "(parents ::shape)"
    assert_raises(Error) { ev("(derive :unqualified ::shape)") } # the global hierarchy wants qualified names
  end

  def test_derivation_errors
    ev "(def h (-> (make-hierarchy) (derive :a :b) (derive :b :c)))"
    assert_equal "Cyclic derivation: :a has :c as ancestor", assert_raises(ExceptionInfo) { ev("(derive h :c :a)") }.message
    assert_equal ":a already has :c as ancestor", assert_raises(ExceptionInfo) { ev("(derive h :a :c)") }.message
    assert_ev true, "(= h (derive h :a :b))"
  end

  def test_classes
    assert_ev true, "(isa? Integer Numeric)"
    assert_ev true, "(isa? Integer Comparable)"
    assert_ev false, "(isa? Numeric Integer)"
    assert_ev true, "(isa? [Integer :a] [Numeric :a])"
    assert_ev false, "(isa? [Integer] [Numeric :a])"
    assert_ev Set[sym_class("Numeric")], "(parents Integer)"
    assert_ev true, "(contains? (ancestors Integer) Comparable)"
    assert_ev true, "(class? String)"
    assert_ev false, "(class? :k)"
    assert_raises(ExceptionInfo) { ev("(descendants Integer)") }
  end

  private

  def sym_class(name)
    Object.const_get(name)
  end
end
