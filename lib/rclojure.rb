require_relative "rclojure/version"
require_relative "rclojure/errors"
require_relative "rclojure/types"
require_relative "rclojure/collections/hash_trie"
require_relative "rclojure/collections/vector"
require_relative "rclojure/collections/map"
require_relative "rclojure/collections/set"
require_relative "rclojure/seqs/cons"
require_relative "rclojure/seqs/array_seq"
require_relative "rclojure/seqs/lazy_seq"
require_relative "rclojure/seqs/range_seq"
require_relative "rclojure/seqs/vector_seq"
require_relative "rclojure/reader"
require_relative "rclojure/printer"
require_relative "rclojure/host"
require_relative "rclojure/string_support"
require_relative "rclojure/namespace"
require_relative "rclojure/nodes"
require_relative "rclojure/fn"
require_relative "rclojure/multi_fn"
require_relative "rclojure/protocol"
require_relative "rclojure/deftype"
require_relative "rclojure/atom"
require_relative "rclojure/analyzer"
require_relative "rclojure/syntax_quote"
require_relative "rclojure/core"
require_relative "rclojure/compiler"
require_relative "rclojure/core_cache"
require_relative "rclojure/runtime"

module RClojure
  def self.read_string(source)
    Reader.read_string(source)
  end

  def self.pr_str(value)
    Printer.pr_str(value)
  end

  @runtime_lock = Mutex.new

  # A Runtime shared by RClojure.eval and friends, created on first use.
  def self.runtime
    @runtime || @runtime_lock.synchronize { @runtime ||= Runtime.new }
  end

  # RClojure.eval("(+ 1 2)"): Runtime#eval on the shared runtime.
  def self.eval(source, **options)
    runtime.eval(source, **options)
  end

  # clj->rb: rclojure collections to Ruby Hashes and Arrays, recursively.
  def self.to_ruby(value)
    Host.to_ruby(value)
  end

  # rb->clj: Ruby Hashes and Arrays to rclojure maps and vectors, recursively.
  def self.from_ruby(value)
    Host.from_ruby(value)
  end
end
