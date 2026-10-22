require "test_helper"

class TestMetadata < Minitest::Test
  include RClojure
  include RClojureTestHelpers
  include EvalTestHelpers

  def test_reader_metadata
    assert_equal Map[{ foo: true }], read("^:foo x").meta
    assert_equal Map[{ tag: sym("String") }], read("^String x").meta
    assert_equal Map[{ tag: "Foo" }], read('^"Foo" x').meta
    assert_equal Map[{ "param-tags": Vector[sym("long")] }], read("^[long] x").meta
    assert_equal Map[{ a: 1 }], read("^{:a 1} [x]").meta
    assert_equal Map[{ b: true, a: true }], read("^:a ^:b x").meta
    assert_equal sym("x"), read("^:foo x") # equality ignores metadata
    assert_raises(ReaderError) { read("^:a 1") }
    assert_raises(ReaderError) { read("^1 x") }
  end

  def test_meta_and_with_meta
    assert_ev Map[{ a: 1 }], "(meta (with-meta [1 2] {:a 1}))"
    assert_ev Map[{ a: 1 }], "(meta (with-meta '(1) {:a 1}))"
    assert_ev Map[{ a: 1 }], "(meta (with-meta (cons 1 nil) {:a 1}))"
    assert_ev Map[{ a: 1 }], "(meta (with-meta {} {:a 1}))"
    assert_ev Map[{ a: 1 }], "(meta (with-meta \#{} {:a 1}))"
    assert_ev Map[{ a: 1 }], "(meta (with-meta 'x {:a 1}))"
    assert_ev Map[{ a: 1, b: 2 }], "(meta (vary-meta (with-meta [] {:a 1}) assoc :b 2))"
    assert_ev nil, "(meta [1])"
    assert_ev nil, "(meta 1)"
    assert_ev true, "(= (with-meta [1] {:a 1}) [1])"
    assert_ev true, "(= (hash (with-meta [1] {:a 1})) (hash [1]))"
    assert_raises(Error) { ev("(with-meta 1 {})") }
  end

  def test_with_meta_on_lazy_seqs_and_fns_keeps_them_working
    ev "(def calls (atom 0))"
    ev "(def s (lazy-seq (swap! calls inc) [1 2]))"
    ev "(def s2 (with-meta s {:m 1}))"
    assert_ev List[1, 2], "(doall s2)"
    assert_ev List[1, 2], "(doall s)"
    assert_ev 1, "@calls" # the body ran once
    assert_ev Map[{ m: 1 }], "(meta s2)"
    assert_ev 8, "((with-meta (fn [x] (* 2 x)) {:m 1}) 4)"
    assert_ev Map[{ m: 1 }], "(meta (with-meta (fn [x] x) {:m 1}))"
  end

  def test_literal_collection_and_fn_metadata_is_evaluated
    assert_ev Map[{ foo: true }], "(meta ^:foo [1])"
    assert_ev Map[{ x: 3 }], "(meta ^{:x (+ 1 2)} {:k 1})"
    assert_ev Map[{ f: true }], "(meta ^:f (fn [] 1))"
    assert_ev Map[{ a: 2 }], "(meta ^{:a (inc 1)} (fn [[x]] x))"
    assert_ev nil, "(meta (fn [] 1))"
    assert_ev Map[{ q: true }], "(meta '^:q sym)"
  end

  def test_syntax_quote_keeps_metadata
    assert_ev Map[{ foo: true }], "(meta `^:foo x)"
    assert_ev Map[{ dynamic: true }], "(meta (second `(def ^:dynamic *x* 1)))"
  end

  def test_var_metadata
    ev '(defn ^:private secret "Docs." {:added "0.1"} [x] x)'
    assert_ev Map[{ private: true, doc: "Docs.", added: "0.1", name: sym("secret") }],
              "(select-keys (meta #'secret) [:private :doc :added :name])"
    assert_ev List[Vector[sym("x")]], "(:arglists (meta #'secret))"
    assert_ev true, "(= *ns* (:ns (meta #'secret)))"
    assert_ev "Doc.", '(def documented "Doc." 1) (:doc (meta #\'documented))'
    assert_ev true, "(:macro (meta #'when))"
    assert_ev "Says hi.", '(defmacro hi "Says hi." [] :hi) (:doc (meta #\'hi))'
    assert_ev :hi, "(hi)"
    # def replaces the metadata, keeping :ns and :name
    assert_ev Map[{ name: sym("redef"), ns: @runtime.find_namespace("user") }], "(def ^:temp redef 1) (def redef 2) (meta #'redef)"
    assert_ev 1, "(alter-meta! #'redef assoc :note 1) (:note (meta #'redef))"
    assert_ev Map[{ only: true }], "(reset-meta! #'redef {:only true}) (meta #'redef)"
  end

  def test_private_vars_from_metadata
    ev "(ns lib.p) (def ^:private hidden 1) (defn- also-hidden [] 2) (def shown 3) (in-ns 'user)"
    assert_ev Vector[sym("shown")], "(vec (keys (ns-publics 'lib.p)))"
    assert_raises(CompilerError) { ev("lib.p/hidden") }
    assert_raises(CompilerError) { ev("(lib.p/also-hidden)") }
    assert_ev 1, "@#'lib.p/hidden"
  end

  def test_namespace_metadata
    assert_ev Map[{ doc: "A namespace.", author: "me" }], '(ns docd "A namespace." {:author "me"}) (meta *ns*)'
    assert_ev Map[{ a: 1 }], "(in-ns 'user) (alter-meta! (the-ns 'docd) (constantly {:a 1})) (meta (the-ns 'docd))"
  end
end

class TestDynamicVars < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def setup
    super
    ev "(def ^:dynamic *depth* 0) (defn depth [] *depth*)"
  end

  def test_binding
    assert_ev Vector[1, 2, 1], "(binding [*depth* 1] [(depth) (binding [*depth* 2] (depth)) (depth)])"
    assert_ev 0, "(depth)"
    assert_ev Vector[1, 2], "(def ^:dynamic *other* :root) (binding [*depth* 1 *other* 2] [*depth* *other*])"
    assert_ev true, "(.dynamic? #'*depth*)"
  end

  def test_binding_is_undone_by_exceptions
    assert_raises(ExceptionInfo) { ev("(binding [*depth* 9] (throw (ex-info \"boom\" {})))") }
    assert_ev 0, "(depth)"
  end

  def test_set_and_var_set
    assert_ev 6, "(binding [*depth* 5] (set! *depth* 6) (depth))"
    assert_ev 7, "(binding [*depth* 5] (var-set #'*depth* 7) (var-get #'*depth*))"
    assert_ev 0, "(depth)"
    error = assert_raises(Error) { ev("(set! *depth* 1)") }
    assert_equal "Can't change/establish root binding of: *depth* with set", error.message
  end

  def test_only_dynamic_vars_can_be_bound
    ev "(def plain 1)"
    error = assert_raises(Error) { ev("(binding [plain 2] plain)") }
    assert_equal "Can't dynamically bind non-dynamic var: user/plain", error.message
  end

  def test_bindings_are_per_thread_but_seen_by_fibers
    assert_ev 0, "(binding [*depth* 1] (.value (Thread/new & (fn [] *depth*))))"
    assert_ev 1, "(binding [*depth* 1] (.resume (Fiber/new & (fn [] *depth*))))"
  end

  def test_var_functions
    assert_ev Vector[true, false], "[(binding [*depth* 1] (thread-bound? #'*depth*)) (thread-bound? #'*depth*)]"
    assert_ev true, "(bound? #'*depth* #'depth)"
    assert_ev false, "(def unset) (bound? #'unset)"
    assert_ev 11, "(def counter 10) (alter-var-root #'counter inc)"
    assert_ev 11, "counter"
    assert_ev 15, "(alter-var-root #'counter + 1 3)"
  end

  def test_with_redefs
    assert_ev :redef, "(with-redefs [depth (constantly :redef)] (depth))"
    assert_ev 0, "(depth)"
    assert_raises(ExceptionInfo) { ev("(with-redefs [depth (constantly 1)] (throw (ex-info \"x\" {})))") }
    assert_ev 0, "(depth)"
  end

  def test_ns_is_dynamic
    assert_ev true, "(.dynamic? #'*ns*)"
    assert_ev "#namespace[elsewhere]", "(binding [*ns* *ns*] (in-ns 'elsewhere) (pr-str *ns*))"
    assert_ev "#namespace[user]", "(pr-str *ns*)"
  end
end
