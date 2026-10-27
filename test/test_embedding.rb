require "test_helper"
require "tmpdir"
require "fileutils"

# The API for Ruby programs running rclojure code (README: "Using rclojure
# from Ruby").
class TestEmbedding < Minitest::Test
  include RClojure

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "my_app"))
    File.write(File.join(@dir, "my_app", "core.clj"), <<~CLJ)
      (ns my-app.core)
      (defn greet [name] (str "hello " name))
      (defmacro twice [x] `(do ~x ~x))
      (def answer 42)
    CLJ
    @rt = Runtime.new(load_path: [@dir])
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_eval
    assert_equal 3, @rt.eval("(+ 1 2)")
    assert_equal 2, @rt.eval("(def x 1) (inc x)")
    assert_equal Vector[1, 2], @rt.eval("[1 2]")
    assert_equal({ a: [1, 2], "s" => [2, 3] }, @rt.eval("{:a [1 2] 's (map inc [1 2])}", ruby: true))
    assert_raises(ReaderError) { @rt.eval("(+ 1") }
    assert_raises(CompilerError) { @rt.eval("(nope)") }
    error = assert_raises(ExceptionInfo) { @rt.eval('(throw (ex-info "bad" {:code 1}))') }
    assert_equal Map[{ code: 1 }], error.data
  end

  def test_eval_in_a_namespace
    @rt.require("my-app.core")
    assert_equal "hello bob", @rt.eval('(greet "bob")', ns: "my-app.core")
    assert_equal :"my-app.core/k", @rt.eval("::k", ns: "my-app.core")
    # The namespace is only bound for the call.
    assert_equal "user", @rt.eval("(name (ns-name *ns*))")
    @rt.eval("(in-ns 'other)", ns: "my-app.core")
    assert_equal "user", @rt.eval("(name (ns-name *ns*))")
    assert_equal 42, @rt.in_ns("my-app.core") { @rt.eval("answer") }
    assert_raises(Error) { @rt.eval("1", ns: "no.such.ns") }
  end

  def test_require_and_vars
    assert_nil @rt.require("my-app.core", "clojure.string")
    assert_equal "hello bob", @rt.fn("my-app.core/greet").call("bob")
    assert_equal "X", @rt.fn("clojure.string/upper-case").("x")
    assert_equal 42, @rt.var("my-app.core/answer").deref
    assert_equal %w[A B], %w[a b].map(&@rt.fn("clojure.string/upper-case"))
    # Vars see redefinition.
    greet = @rt.fn("my-app.core/greet")
    @rt.eval('(defn greet [name] (str "hi " name))', ns: "my-app.core")
    assert_equal "hi bob", greet.("bob")
  end

  def test_var_requires_its_namespace
    assert_equal 42, Runtime.new(load_path: [@dir]).var("my-app.core/answer").deref
  end

  def test_var_errors
    assert_raises(ArgumentError) { @rt.var("greet") }
    assert_raises(Error) { @rt.var("clojure.core/no-such-fn") }
    assert_raises(Error) { @rt.var("no.such.lib/x") }
    assert_raises(Error) { @rt.fn("my-app.core/twice") }
    assert_raises(Error) { @rt.fn("my-app.core/answer") }
  end

  def test_ruby_arguments_pass_through
    sum = @rt.fn("clojure.core/reduce")
    assert_equal 6, sum.(@rt.fn("clojure.core/+"), [1, 2, 3])
    assert_equal 1, @rt.fn("clojure.core/get").({ a: 1 }, :a)
    assert_equal Vector[1, 2], @rt.fn("clojure.core/conj").(RClojure.from_ruby([1]), 2)
    assert_equal({ a: [1] }, RClojure.to_ruby(@rt.eval("{:a (list 1)}")))
  end

  def test_define
    var = @rt.define("my.helpers/shout") { |s| "#{s.upcase}!" }
    assert_equal "#'my.helpers/shout", var.to_s
    assert_equal "HI!", @rt.eval('(my.helpers/shout "hi")')
    @rt.define("user/add", ->(a, b) { a + b })
    assert_equal List[3, 5], @rt.eval("(map add [1 2] [2 3])")
    assert_raises(ArityError) { @rt.eval("(add 1)") }
    # Blocks are lenient about args, as in Ruby.
    @rt.define("user/first-arg") { |a, _b| a }
    assert_equal 1, @rt.eval("(first-arg 1)")
    @rt.define("user/size", "abc".method(:size))
    assert_equal 3, @rt.eval("(size)")
    assert_raises(ArgumentError) { @rt.define("user/nothing") }
  end

  def test_shared_runtime
    assert_same RClojure.runtime, RClojure.runtime
    assert_equal List[2, 3, 4], RClojure.eval("(map inc [1 2 3])")
    assert_equal [2, 3], RClojure.eval("(map inc [1 2])", ruby: true)
  end
end
