require "minitest/autorun"
require "tmpdir"

# Keep the core cache out of the user's cache directory (an empty
# RCLOJURE_CACHE_DIR runs the suite uncached).
ENV["RCLOJURE_CACHE_DIR"] ||= File.join(Dir.tmpdir, "rclojure-test-cache")

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
