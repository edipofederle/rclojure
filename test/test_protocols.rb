require "test_helper"

class TestProtocols < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def setup
    super
    ev <<~CLJ
      (defprotocol Shape
        "Things with an area."
        (area [s] "The area.")
        (scale [s k]))
    CLJ
  end

  def test_defprotocol
    assert_ev Symbol.new(nil, "P"), "(defprotocol P (m [x]))"
    assert_ev "Things with an area.", "(:doc (meta #'Shape))"
    assert_ev "The area.", "(:doc (meta #'area))"
    assert_ev List[Vector[Symbol.new(nil, "s")]], "(:arglists (meta #'area))"
    assert_ev true, "(= #'Shape (:protocol (meta #'scale)))"
    assert_ev "#<protocol user/Shape>", "(pr-str Shape)"
    assert_raises(CompilerError) { ev("(defprotocol Bad (m []))") }
    assert_raises(CompilerError) { ev("(defprotocol Bad (m [x]) (m [x y]))") }
  end

  def test_extend_type_and_protocol
    ev <<~CLJ
      (extend-type String Shape (area [s] (count s)))
      (extend-protocol Shape
        nil (area [_] 0)
        Numeric (area [n] (* n n)) (scale ([n k] (* n k))))
    CLJ
    assert_ev List[4, 0, 9, 2.25], '(map area ["abcd" nil 3 1.5])'
    assert_ev 6, "(scale 3 2)"
    assert_ev true, "(satisfies? Shape 1)"
    assert_ev false, "(satisfies? Shape :k)"
    assert_ev true, "(extends? Shape String)"
    assert_ev true, "(extends? Shape nil)"
    assert_ev false, "(extends? Shape Integer)"
    assert_ev Set[String, nil, Numeric], "(set (map identity (extenders Shape)))"
    assert_ev 5, '(extend String Shape {:area (fn [s] (inc (count s)))}) (area "abcd")'
  end

  def test_dispatch_follows_ancestors
    ev "(extend-protocol Shape Object (area [_] :object) Comparable (area [_] :comparable))"
    assert_ev List[:comparable, :object, :comparable], '(map area [1 [] "s"])'
    # As in Clojure, nil isn't an Object.
    error = assert_raises(ArgumentError) { ev("(area nil)") }
    assert_equal "No implementation of method: :area of protocol: #'user/Shape found for class: nil", error.message
    error = assert_raises(ArgumentError) { ev("(scale 1 2)") }
    assert_equal "No implementation of method: :scale of protocol: #'user/Shape found for class: Integer", error.message
  end

  def test_extend_errors
    assert_raises(ArgumentError) { ev("(extend String Shape {:perimeter identity})") }
    assert_raises(ArgumentError) { ev("(extend String :not-a-protocol {})") }
    assert_raises(ArgumentError) { ev("(deftype T [] Shape (area [_] 1)) (extend T Shape {:area identity})") }
  end

  def test_extend_via_metadata
    ev "(defprotocol Named :extend-via-metadata true (nm [x]))"
    ev "(extend-type Object Named (nm [_] :extended))"
    assert_ev :meta, "(nm (with-meta [] {`nm (fn [_] :meta)}))"
    assert_ev :extended, "(nm [])"
    assert_ev :direct, "(nm (with-meta (reify Named (nm [_] :direct)) {`nm (fn [_] :meta)}))"
  end

  def test_deftype
    ev <<~CLJ
      (deftype Circle [r]
        Shape
        (area [_] (* 3 r r))
        (scale [this k] (Circle. (* r k)))
        Object
        (to_s [_] (str "circle " r)))
    CLJ
    assert_ev 12, "(area (scale (->Circle 1) 2))"
    assert_ev 2, "(.-r (Circle. 2))"
    assert_ev "circle 2", "(str (Circle. 2))"
    assert_ev true, "(instance? Circle (Circle. 1))"
    assert_ev "user.Circle", "(pr-str Circle)"
    assert_match(/\A#object\[user\.Circle 0x\h+ "circle 1"\]\z/, ev("(pr-str (Circle. 1))"))
    assert_ev false, "(= (Circle. 1) (Circle. 1))"
    assert_ev true, "(.frozen? (Circle. 1))"
    assert_ev true, "(satisfies? Shape (Circle. 1))"
    assert_ev nil, "(extenders Shape)"
    assert_raises(ArityError) { ev("(Circle.)") }
    assert_raises(ArityError) { ev("(->Circle)") }
  end

  def test_deftype_methods
    ev <<~CLJ
      (defprotocol P (m [x] [x a]) (n [x]))
      (deftype Methods [x]
        P
        (m [_] x)
        (m [this a] (if (pos? a) (recur (dec a)) (m this)))
        (n [_] (fn [] x)))
      (deftype Destructured [] P (m [_ {:keys [a b]}] (+ a b)))
    CLJ
    assert_ev 1, "(m (Methods. 1))"
    assert_ev 1, "(m (Methods. 1) 10000)"
    assert_ev 2, "((n (Methods. 2)))"
    assert_ev 3, "(m (Destructured.) {:a 1 :b 2})"
    assert_raises(ArgumentError) { ev("(deftype Bad [] P (zzz [_]))") }
    assert_raises(ArgumentError) { ev("(deftype Bad [] P (m [_ a b]))") }
    # Methods aren't closures, as in Clojure.
    assert_raises(CompilerError) { ev("(let [y 1] (deftype Bad [] P (n [_] y)))") }
  end

  def test_protocol_methods_dont_replace_ruby_methods
    ev "(defprotocol Hashy (hash [x]) (to_s [x]))"
    ev "(deftype H [] Hashy (hash [_] :hashy) (to_s [_] :to-s))"
    assert_ev :hashy, "(user/hash (H.))"
    assert_ev true, "(integer? (clojure.core/hash (H.)))"
    assert_ev true, '(.start-with? (.to-s (H.)) "user.H@")'
  end

  def test_mutable_fields
    ev <<~CLJ
      (deftype Counter [^:unsynchronized-mutable n]
        Object
        (inc! [this] (set! n (inc n)) this)
        (value [_] n))
    CLJ
    assert_ev 2, "(.value (.inc! (.inc! (Counter. 0))))"
    assert_ev false, "(.frozen? (Counter. 0))"
    assert_raises(NoMethodError) { ev("(.-n (Counter. 0))") }
    error = assert_raises(CompilerError) { ev("(deftype Fixed [n] Object (bump [_] (set! n 1)))") }
    assert_equal "Cannot assign to non-mutable: n", error.message
  end

  def test_ruby_modules_and_object_methods
    ev <<~CLJ
      (deftype Bag [items]
        Enumerable
        (each [this & f] (doseq [i items] (f i)) this))
      (deftype Version [n]
        Comparable
        (<=> [_ other] (compare n (.-n other)))
        Object
        (== [_ other] (and (instance? Version other) (= n (.-n other))))
        (eql? [this other] (= this other))
        (hash [_] (hash n)))
    CLJ
    assert_equal [2, 3, 4], ev("(.map (Bag. [1 2 3]) & inc)")
    assert_equal [1, 2], ev("(.sort (Bag. [2 1]))")
    assert_ev true, "(< (Version. 1) (Version. 2))"
    assert_ev true, "(= (Version. 1) (Version. 1))"
    assert_ev 1, "(count (hash-set (Version. 1) (Version. 1)))"
    assert_ev List[1, 3], "(map #(.-n %) (sort [(Version. 3) (Version. 1)]))"
    assert_raises(ArgumentError) { ev("(deftype Bad [] String (size [_] 0))") }
  end

  def test_defrecord
    ev <<~CLJ
      (defrecord Rect [w h]
        Shape
        (area [_] (* w h))
        (scale [this k] (assoc this :w (* w k) :h (* h k))))
      (def r (->Rect 2 3))
    CLJ
    assert_ev 6, "(area r)"
    assert_ev 24, "(area (scale r 2))"
    assert_ev "#user.Rect{:w 4, :h 6}", "(pr-str (scale r 2))"
    assert_ev 2, "(:w r)"
    assert_ev 2, "(.-w r)"
    assert_ev Vector[2, 3], "(let [{:keys [w h]} r] [w h])"
    assert_ev true, "(record? r)"
    assert_ev false, "(record? {:w 2 :h 3})"
    assert_ev true, "(map? r)"
    assert_ev true, "(instance? Rect r)"
    assert_ev true, "(= r (Rect. 2 3))"
    assert_ev false, "(= r {:w 2 :h 3})"
    assert_ev false, "(= {:w 2 :h 3} r)"
    assert_ev true, "(= (hash r) (hash (->Rect 2 3)))"
  end

  def test_records_are_maps
    ev "(defrecord R [a b]) (def r (->R 1 2))"
    assert_ev "#user.R{:a 1, :b 2, :c 3}", "(pr-str (assoc r :c 3))"
    assert_ev 3, "(count (assoc r :c 3))"
    assert_ev true, "(= r (dissoc (assoc r :c 3) :c))"
    assert_ev Map[{ b: 2 }], "(dissoc r :a)"
    assert_ev false, "(record? (dissoc r :a))"
    assert_ev Map[{ m: 1 }], "(meta (dissoc (with-meta r {:m 1}) :a))"
    assert_ev List[Vector[:a, 1], Vector[:b, 2]], "(seq r)"
    assert_ev List[:a, :b], "(keys r)"
    assert_ev List[1, 2], "(vals r)"
    assert_ev Map[{ a: 1, b: 2 }], "(into {} r)"
    assert_ev "#user.R{:a 9, :b 2, :z 1}", "(pr-str (conj (merge r {:a 9}) [:z 1]))"
    assert_ev true, "(contains? r :a)"
    assert_ev :nf, "(get r :c :nf)"
    assert_ev Map[{ m: 1 }], "(meta (with-meta r {:m 1}))"
    assert_ev true, "(= r (with-meta r {:m 1}))"
    assert_ev "#user.R{:a 1, :b nil, :c 3}", "(pr-str (map->R {:a 1 :c 3}))"
    assert_ev "#user.R{:a 1, :b 2, :e 3}", "(pr-str (R. 1 2 {:x 1} {:e 3}))"
    assert_ev true, "(.frozen? r)"
  end

  def test_record_fields_named_like_map_methods
    ev "(defrecord Stats [count keys])"
    assert_ev Vector[5, 6], "(let [s (->Stats 5 6)] [(:count s) (:keys s)])"
    assert_ev 2, "(count (->Stats 5 6))"
  end

  def test_defrecord_errors
    assert_raises(CompilerError) { ev("(defrecord Bad [^:unsynchronized-mutable a])") }
    assert_raises(CompilerError) { ev("(defrecord Bad [:a])") }
    assert_raises(CompilerError) { ev("(defrecord Bad (a))") }
  end

  def test_reify
    ev "(defn make [x] (reify Shape (area [_] x) (scale [_ k] (make (* x k)))))"
    assert_ev 12, "(area (scale (make 4) 3))"
    assert_ev true, "(identical? (class (make 1)) (class (make 2)))"
    assert_ev Map[{ k: 1 }], "(meta ^{:k 1} (reify Shape (area [_] 1)))"
    # Each object keeps the loop locals it closed over.
    assert_ev List[0, 1, 2], "(loop [i 0 acc []] (if (< i 3) (recur (inc i) (conj acc (reify Shape (area [_] i)))) (map area acc)))"
  end

  def test_reify_closes_over_fields
    ev "(deftype Outer [x] Shape (area [this] (reify Shape (area [_] [x this]))))"
    assert_ev true, "(let [o (Outer. 5)] (= [5 o] (area (area o))))"
  end
end
