require "test_helper"

class TestPrinter < Minitest::Test
  include RClojureTestHelpers

  ROUND_TRIP = [
    "nil", "true", "false", "42", "-7", "3.5", "1/2", '"a\nb \"q\""',
    "foo", "clojure.core/map", ":kw", ":ns/kw",
    "(1 (2 3) [])", "[1 :a \"s\"]", "{:a 1, :b [2]}", "\#{1}", "(quote x)"
  ].freeze

  def test_round_trips
    ROUND_TRIP.each do |source|
      assert_equal source, RClojure.pr_str(read(source)), "round-tripping #{source}"
    end
  end
end
