require "minitest/autorun"
require "rclojure"

module RClojureTestHelpers
  def read(source)
    RClojure.read_string(source)
  end

  def sym(text)
    RClojure::Symbol.parse(text)
  end
end

module EvalTestHelpers
  def setup
    @runtime = RClojure::Runtime.new
  end

  def ev(source)
    @runtime.eval_string(source)
  end

  def assert_ev(expected, source)
    expected.nil? ? assert_nil(ev(source)) : assert_equal(expected, ev(source))
  end
end
