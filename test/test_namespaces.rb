require "test_helper"
require "tmpdir"
require "fileutils"

class TestNamespaces < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def setup
    @dir = Dir.mktmpdir
    @runtime = RClojure::Runtime.new(load_path: [@dir])
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write_lib(path, source)
    file = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, source)
  end

  def test_ns_switches_and_refers_core
    assert_ev Symbol.parse("foo.bar"), "(ns foo.bar) (ns-name *ns*)"
    ev "(def x (inc 1))"
    assert_ev "#'foo.bar/x", "(str (var x))"
    ev "(in-ns 'user)"
    assert_ev 2, "foo.bar/x"
    assert_ev "#namespace[user]", "(pr-str *ns*)"
  end

  def test_in_ns_creates_a_bare_namespace
    ev "(in-ns 'bare)"
    assert_raises(CompilerError) { ev("(inc 1)") }
    assert_ev 2, "(clojure.core/refer 'clojure.core) (inc 1)"
  end

  def test_top_level_do_evaluates_forms_one_by_one
    assert_ev Symbol.parse("q.r/z"), "(do (ns q.r) (def z 1)) (symbol (str (.-name (.-ns (var z)))) \"z\")"
  end

  def test_qualified_symbol_errors
    ev "(ns foo.bar) (def x 1) (in-ns 'user)"
    error = assert_raises(CompilerError) { ev("foo.bar/nope") }
    assert_equal "No such var: foo.bar/nope", error.message
    error = assert_raises(CompilerError) { ev("nope.ns/x") }
    assert_equal "Unable to resolve symbol: nope.ns/x in this context", error.message
  end

  def test_private_vars
    ev "(ns lib.a) (defn- secret [] :s) (defn open [] (secret))"
    assert_ev :s, "(secret)"
    ev "(in-ns 'user)"
    assert_ev :s, "(lib.a/open)"
    error = assert_raises(CompilerError) { ev("(lib.a/secret)") }
    assert_equal "var: #'lib.a/secret is not public", error.message
    assert_ev :s, "((var lib.a/secret))"
    assert_ev Vector[Symbol.parse("open")], "(vec (keys (ns-publics 'lib.a)))"
    assert_ev 2, "(count (ns-interns 'lib.a))"
    assert_ev false, "(contains? (ns-publics 'clojure.core) 'check-bindings)"
  end

  def test_refer_filters
    ev "(ns lib.b) (defn f [] :f) (defn g [] :g) (defn h [] :h) (defn- p [] :p) (in-ns 'user)"
    assert_ev :f, "(refer 'lib.b :only '[f]) (f)"
    assert_raises(CompilerError) { ev("(g)") }
    assert_ev :g, "(refer 'lib.b :exclude '[f h] :rename '{g gee}) (gee)"
    assert_raises(CompilerError) { ev("(g)") }
    assert_raises(CompilerError) { ev("(h)") }
    assert_equal "nope does not exist", assert_raises(Error) { ev("(refer 'lib.b :only '[nope])") }.message
    assert_equal "p is not public", assert_raises(Error) { ev("(refer 'lib.b :only '[p])") }.message
    assert_raises(Error) { ev("(refer 'no.such.ns)") }
  end

  def test_replacing_mappings
    ev "(ns lib.c) (defn shout [] :theirs) (in-ns 'user)"
    _, err = capture_io { ev("(def shout :mine) (refer 'lib.c)") }
    assert_match "REJECTED: attempt to replace interned var #'user/shout with #'lib.c/shout", err
    assert_ev :mine, "shout"
    _, err = capture_io { ev("(def inc :mine)") }
    assert_match "WARNING: inc already refers to: #'clojure.core/inc in namespace: user", err
    assert_ev :mine, "inc"
  end

  def test_aliases
    ev "(ns lib.d) (def x 1) (in-ns 'user)"
    ev "(alias 'd 'lib.d)"
    assert_ev 1, "d/x"
    assert_ev Map[{ Symbol.parse("d") => @runtime.find_namespace("lib.d") }], "(ns-aliases *ns*)"
    assert_ev Symbol.parse("lib.d/x"), "`d/x"
    ev "(ns lib.e)"
    error = assert_raises(Error) { ev("(in-ns 'user) (alias 'd 'lib.e)") }
    assert_equal "Alias d already exists in namespace user, aliasing lib.d", error.message
    assert_ev nil, "(ns-unalias *ns* 'd)"
    assert_raises(CompilerError) { ev("d/x") }
  end

  def test_auto_resolved_keywords
    assert_ev :"a.b/k", "(ns a.b) ::k"
    assert_ev :"a.b/k", '(read-string "::k")'
    assert_ev :"a.b/k", "(in-ns 'user) (alias 'ab 'a.b) ::ab/k"
    assert_raises(ReaderError) { ev("::nope/k") }
    assert_raises(ReaderError) { RClojure.read_string("::k") }
  end

  def test_syntax_quote_leaves_dotted_names_alone
    assert_ev Symbol.parse("clojure.core"), "`clojure.core"
    assert_ev Symbol.parse("my.Thing"), "`my.Thing"
  end

  def test_namespace_functions
    assert_ev "#'clojure.core/inc", "(str (resolve 'inc))"
    assert_ev String, "(resolve 'String)"
    assert_ev nil, "(resolve 'nope)"
    assert_ev nil, "(resolve {'inc 1} 'inc)"
    assert_ev "#'clojure.core/map", "(str (ns-resolve 'clojure.core 'map))"
    assert_ev "#'clojure.core/inc", "(str (find-var 'clojure.core/inc))"
    assert_ev nil, "(find-var 'clojure.core/nope)"
    assert_raises(ArgumentError) { ev("(find-var 'inc)") }
    assert_ev 5, "(intern 'user 'five 5) five"
    assert_ev true, "(var? (var five))"
    assert_ev nil, "(find-ns 'made)"
    assert_ev "made", "(name (ns-name (create-ns 'made)))"
    assert_ev true, "(boolean (some \#{(find-ns 'made)} (all-ns)))"
    assert_ev nil, "(remove-ns 'made) (find-ns 'made)"
    assert_raises(Error) { ev("(remove-ns 'clojure.core)") }
    assert_raises(Error) { ev("(the-ns 'nope)") }
    assert_ev nil, "(ns-unmap *ns* 'five)"
    assert_raises(CompilerError) { ev("five") }
  end

  def test_require_loads_libs_from_the_load_path
    write_lib "my_app/util.clj", <<~CLJ
      (ns my-app.util)
      (defn shout [s] (str (.upcase s) "!"))
      (defn whisper [s] (.downcase s))
      (defmacro twice [x] `(do ~x ~x))
    CLJ
    write_lib "my_app/core.clj", <<~CLJ
      (ns my-app.core
        "The app."
        {:author "me"}
        (:require [my-app.util :as u :refer [shout]])
        (:gen-class))
      (defn greet [n] (shout (str "hi " n)))
      (def lower (u/whisper "LOW"))
    CLJ
    assert_ev nil, "(require 'my-app.core)"
    assert_ev "HI BOB!", '(my-app.core/greet "bob")'
    assert_ev "low", "my-app.core/lower"
    assert_ev "#namespace[user]", "(pr-str *ns*)"
    assert_ev true, "(contains? (loaded-libs) 'my-app.util)"
    assert_ev "x", '(require \'[my-app.util :as util :refer :all]) (whisper "X")'
    assert_ev 1, "(util/twice 1)"
    assert_ev "Y!", '(use \'my-app.util) (shout "y")'
  end

  def test_require_loads_once_unless_reloading
    ev "(def loads (atom 0))"
    write_lib "counted.clj", "(ns counted) (swap! user/loads inc)"
    ev "(require 'counted) (require 'counted)"
    assert_ev 1, "@loads"
    ev "(require 'counted :reload)"
    assert_ev 2, "@loads"
  end

  def test_prefix_lists_and_as_alias
    write_lib "pre/one.clj", "(ns pre.one) (def v 1)"
    write_lib "pre/two_x.clj", "(ns pre.two-x) (def v 2)"
    assert_ev 3, "(require '(pre [one :as o] [two-x :as t])) (+ o/v t/v)"
    assert_raises(Error) { ev("(require '(pre [a.b]))") }
    assert_ev :"not.loaded/k", "(require '[not.loaded :as-alias nl]) ::nl/k"
  end

  def test_require_errors
    error = assert_raises(Error) { ev("(require 'no.such-lib)") }
    assert_equal "Could not locate no/such_lib.clj on load path: #{@dir}:#{Runtime::BUILTIN_SOURCES}", error.message
    assert_raises(ExceptionInfo) { ev("(require 'x :bogus)") }
    assert_raises(ExceptionInfo) { ev("(require)") }

    write_lib "broken.clj", "(ns broken) (def x (throw (ex-info \"boom\" {})))"
    assert_raises(ExceptionInfo) { ev("(require 'broken)") }
    assert_ev nil, "(find-ns 'broken)"

    write_lib "wrong_ns.clj", "(ns something-else)"
    error = assert_raises(ExceptionInfo) { ev("(require '[wrong-ns :as w])") }
    assert_equal "namespace 'wrong-ns' not found after loading '/wrong_ns'", error.message
  end

  def test_cyclic_dependencies_are_detected
    write_lib "cyc/a.clj", "(ns cyc.a (:require [cyc.b]))"
    write_lib "cyc/b.clj", "(ns cyc.b (:require [cyc.a]))"
    error = assert_raises(ExceptionInfo) { ev("(require 'cyc.a)") }
    assert_equal "Cyclic load dependency: [ /cyc/a ]->/cyc/b->[ /cyc/a ]", error.message
  end

  def test_load_and_load_file
    write_lib "app/helpers.clj", "(def helper :h)"
    assert_ev :h, "(ns app.main) (load \"helpers\") helper"
    write_lib "script.clj", "(ns scripted) (def s :ran) s"
    assert_ev :ran, "(in-ns 'user) (load-file \"#{File.join(@dir, 'script.clj')}\")"
    assert_ev "#namespace[user]", "(pr-str *ns*)"
  end

  def test_unsupported_ns_clauses
    assert_raises(CompilerError) { ev("(ns imports (:import [Foo]))") }
  end
end
