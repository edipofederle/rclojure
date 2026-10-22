require "test_helper"

# Characters and strings as seqs, regexes, sorting, letfn/defonce and the
# clojure.string / clojure.set libs.
class TestEveryday < Minitest::Test
  include RClojure
  include EvalTestHelpers

  def test_strings_are_seqs_of_characters
    assert_ev "a", "(first \"abc\")"
    assert_ev List["b", "c"], "(rest \"abc\")"
    assert_ev "cba", "(apply str (reverse \"abc\"))"
    assert_ev Vector["h", "é"], "(vec \"hé\")"
    assert_ev "b", "(nth \"abc\" 1)"
    assert_ev nil, "(get \"abc\" 5)"
    assert_ev nil, "(seq \"\")"
    assert_ev Map[{ "a" => 2, "b" => 1 }], "(frequencies \"aba\")"
    assert_ev true, "(= \\a \"a\")" # characters are one-character strings
    assert_ev "ab", "(str \\a \\b)"
  end

  def test_character_functions
    assert_ev true, "(char? \\a)"
    assert_ev false, "(char? \"ab\")"
    assert_ev 97, "(int \\a)"
    assert_ev "λ", "(char 955)"
    assert_ev "a", "(char \\a)"
    assert_raises(ArgumentError) { ev("(char \"ab\")") }
    assert_ev 3, "(int 3.9)"
    assert_ev 1.0, "(double 1)"
  end

  def test_anonymous_fns_and_var_quotes
    assert_ev List[1, 4, 9], "(map #(* % %) [1 2 3])"
    assert_ev Vector[:b, :a], "(#(vector %2 %1) :a :b)"
    assert_ev 6, "(#(apply + %&) 1 2 3)"
    assert_ev "#'clojure.core/map", "(str #'map)"
    assert_ev 3, "(#'+ 1 2)"
  end

  def test_regexes
    assert_ev "123", '(re-find #"\d+" "abc123def456")'
    assert_ev Vector["a1", "a", "1"], '(re-find #"(\w)(\d)" "a1")'
    assert_ev Vector["a", "a", nil], '(re-find #"(\w)(\d)?" "a")'
    assert_ev nil, '(re-find #"z" "abc")'
    assert_ev "123", '(re-matches #"\d+" "123")'
    assert_ev nil, '(re-matches #"\d+" "123x")'
    assert_ev List["1", "2", "3"], '(re-seq #"\d" "a1b2c3")'
    assert_ev List["", "", ""], '(re-seq #"x*" "ab")'
    assert_ev nil, '(re-seq #"z" "abc")'
    assert_ev List["a", "a"], '(take 2 (re-seq #"a" (apply str (repeat 10000 "a"))))'
    assert_ev "oo", '(re-find (re-pattern "o+") "foo")'
    assert_ev "a+b", '(str #"a+b")'
    assert_ev '#"a+b"', '(pr-str #"a+b")'
  end

  def test_compare
    assert_ev(-1, "(compare 1 2)")
    assert_ev 0, "(compare 1 1.0)"
    assert_ev(-1, "(compare nil 0)")
    assert_ev(-1, "(compare false true)")
    assert_ev(-1, "(compare :a :a/b)") # no namespace sorts first
    assert_ev(-1, "(compare 'a/z 'b/a)")
    assert_ev(-1, "(compare [1 2] [1 3])")
    assert_ev 1, "(compare [1 2 3] [9])" # longer vectors are greater
    assert_raises(ArgumentError) { ev("(compare \"a\" 1)") }
    assert_raises(ArgumentError) { ev("(compare '(1) '(2))") }
  end

  def test_sort
    assert_ev List[1, 2, 3], "(sort [3 1 2])"
    assert_ev List[3, 2, 1], "(sort > [3 1 2])"
    assert_ev List[3, 2, 1], "(sort (fn [a b] (- b a)) [1 3 2])"
    assert_ev List::EMPTY, "(sort [])"
    assert_ev List::EMPTY, "(sort nil)"
    assert_ev List[nil, :a, :b, :"a/z"], "(sort [:a/z :b nil :a])"
    assert_ev List["a", "bb", "ccc"], '(sort-by count ["ccc" "a" "bb"])'
    assert_ev List[Vector[3, :b], Vector[1, :a]], "(sort-by first > [[1 :a] [3 :b]])"
    # stable: equal keys keep their order
    assert_ev List[2, 1, 3], "(map :id (sort-by :k [{:k 2 :id 1} {:k 1 :id 2} {:k 2 :id 3}]))"
    assert_raises(ArgumentError) { ev("(sort (fn [a b] :x) [1 2])") }
  end

  def test_letfn
    assert_ev Vector[true, true],
              "(letfn [(ev? [n] (if (zero? n) true (od? (dec n))))
                       (od? [n] (if (zero? n) false (ev? (dec n))))]
                 [(ev? 10) (od? 7)])"
    assert_ev 1, "(letfn [(f [] 1)] (f))"
    assert_ev 5, "(loop [i 0] (letfn [(f [] i)] (if (< i 5) (recur (inc i)) (f))))"
    # fns made by a letfn in a loop keep that iteration's values
    assert_ev Vector[0, 1, 2],
              "(loop [i 0 fs []]
                 (if (< i 3)
                   (letfn [(g [] i) (h [] (g))] (recur (inc i) (conj fs h)))
                   (mapv #(%) fs)))"
    assert_raises(CompilerError) { ev("(letfn* [f])") }
  end

  def test_defonce
    assert_ev "#'user/once", "(str (defonce once (atom 1)))"
    assert_ev nil, "(defonce once (atom 2))"
    assert_ev 1, "@once"
  end

  def test_clojure_string
    ev "(require '[clojure.string :as str])"
    assert_ev Vector["a", "b", "c"], '(str/split "a1b22c" #"\d+")'
    assert_ev Vector["a", "b"], '(str/split "a,b,,," #",")'
    assert_ev Vector["a", "b", "", "", ""], '(str/split "a,b,,," #"," -1)'
    assert_ev Vector["a", "b,c"], '(str/split "a,b,c" #"," 2)'
    assert_ev Vector["a", "b", "c"], '(str/split "a1b2c" #"(\d)")' # groups aren't kept, unlike Ruby
    assert_ev Vector["a", "b", "c"], '(str/split "abc" #"")'
    assert_ev Vector["abc"], '(str/split "abc" #",")'
    assert_ev Vector["a", "b"], "(str/split-lines \"a\\r\\nb\")"
    assert_ev "lmostAay igPay atinLay", '(str/replace "Almost Pig Latin" #"\b(\w)(\w+)\b" "$2$1ay")'
    assert_ev "a$b", '(str/replace "a.b" "." "$")'
    assert_ev "a<b>c", '(str/replace "abc" #"b" #(str "<" % ">"))'
    assert_ev "a$1c", '(str/replace "abc" #"b" (str/re-quote-replacement "$1"))'
    assert_ev "first swap two", '(str/replace-first "swap first two" #"(\w+)(\s+)(\w+)" "$3$2$1")'
    assert_ev "xbb", '(str/replace-first "bbb" "b" "x")'
    assert_ev "1, 2, 3", '(str/join ", " [1 2 3])'
    assert_ev "123", "(str/join [1 2 3])"
    assert_ev "Hello", '(str/capitalize "hELLO")'
    assert_ev "ABC", '(str/upper-case "abc")'
    assert_ev "hi", "(str/trim \"  hi \\t\\n\")"
    assert_ev "hi  ", '(str/triml "  hi  ")'
    assert_ev "  hi", '(str/trimr "  hi  ")'
    assert_ev "x", "(str/trim-newline \"x\\r\\n\")"
    assert_ev true, '(str/blank? " \t ")'
    assert_ev true, "(str/blank? nil)"
    assert_ev "a&lt;b", '(str/escape "a<b" {\< "&lt;"})'
    assert_ev 2, '(str/index-of "hello" \l)'
    assert_ev 3, '(str/index-of "hello" "l" 3)'
    assert_ev nil, '(str/index-of "hello" "z")'
    assert_ev 3, '(str/last-index-of "hello" "l")'
    assert_ev true, '(str/starts-with? "hello" "he")'
    assert_ev true, '(str/ends-with? "hello" "lo")'
    assert_ev true, '(str/includes? "hello" "ell")'
    assert_ev "cba", '(str/reverse "abc")'
    assert_ev 3, "(count \"abc\")" # core's reverse and replace are untouched
  end

  def test_clojure_set
    ev "(require '[clojure.set :as set])"
    assert_ev Set[1, 2, 3, 4], "(set/union \#{1 2} \#{2 3} \#{4})"
    assert_ev Set[], "(set/union)"
    assert_ev Set[2, 3], "(set/intersection \#{1 2 3} \#{2 3 4})"
    assert_ev Set[1], "(set/difference \#{1 2 3} \#{2} \#{3})"
    assert_ev Set[2, 4], "(set/select even? \#{1 2 3 4})"
    assert_ev Set[Map[{ a: 1 }]], "(set/project \#{{:a 1 :b 2}} [:a])"
    assert_ev Map[{ b: 2, x: 1 }], "(set/rename-keys {:a 1 :b 2} {:a :x})"
    assert_ev Map[{ 1 => :a }], "(set/map-invert {:a 1})"
    assert_ev Map[{ Map[{ a: 1 }] => Set[Map[{ a: 1, b: 2 }], Map[{ a: 1, b: 3 }]] }],
              "(set/index \#{{:a 1 :b 2} {:a 1 :b 3}} [:a])"
    assert_ev Set[Map[{ id: 1, n: "a", x: 9 }]],
              '(set/join #{{:id 1 :n "a"} {:id 2 :n "b"}} #{{:id 1 :x 9}})'
    assert_ev Set[Map[{ id: 1, owner: 1, x: 9 }]],
              "(set/join \#{{:id 1}} \#{{:owner 1 :x 9}} {:id :owner})"
    assert_ev true, "(set/subset? \#{1} \#{1 2})"
    assert_ev false, "(set/superset? \#{1} \#{1 2})"
  end
end
