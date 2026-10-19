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
