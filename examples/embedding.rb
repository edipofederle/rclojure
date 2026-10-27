# Running rclojure code from a Ruby program: ruby -Ilib examples/embedding.rb
require "rclojure"

rt = RClojure::Runtime.new(load_path: [File.join(__dir__, "src")])

# Clojure code can call functions written in Ruby.
STOPWORDS = %w[the a of and].freeze
rt.define("helpers/stopword?") { |word| STOPWORDS.include?(word) }

rt.require("greeter.core")
greet = rt.fn("greeter.core/greet")
puts greet.("ada")                                 # Hello, Ada!
puts %w[alan grace].map(&greet).inspect            # ["Hello, Alan!", "Hello, Grace!"]

text = "The cat and the hat and the bat sat on the mat of the cat"
puts RClojure.pr_str(rt.fn("greeter.core/report").(text)) # (["cat" 2] ["hat" 1] ["bat" 1])
p rt.eval("(report #{text.inspect})", ns: "greeter.core", ruby: true) # Ruby data: [["cat", 2], ...]

puts rt.fn("greeter.core/to-json").({ "name" => "ada", "langs" => %w[clj rb] })

begin
  rt.eval('(throw (ex-info "Out of greetings" {:left 0}))')
rescue RClojure::ExceptionInfo => e
  puts "#{e.message}: #{e.data[:left]}"            # Out of greetings: 0
end

# One-off evaluation on a shared runtime.
p RClojure.eval("(map inc [1 2 3])", ruby: true)    # [2, 3, 4]
