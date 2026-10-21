require "digest"
require "fileutils"

module RClojure
  # Caches core.clj compiled to Ruby bytecode, so a Runtime can run it
  # without reading, macroexpanding and compiling the source (most of its
  # startup time). Each form's compiled source is joined into one lambda,
  # stored as an InstructionSequence binary (as bootsnap does), with the
  # forms' constants marshaled alongside. The cache file's name is a
  # digest of everything that shapes it: rclojure's sources and the Ruby
  # build.
  class CoreCache
    SOURCES = Dir[File.join(__dir__, "**", "*.{rb,clj}")].sort.freeze

    # RCLOJURE_CACHE_DIR, else rclojure/ in the XDG cache directory. nil
    # (no caching) when RCLOJURE_CACHE_DIR is empty, or there's no home
    # directory to put the cache in.
    def self.default_dir
      dir = ENV.fetch("RCLOJURE_CACHE_DIR") do
        File.join(ENV.fetch("XDG_CACHE_HOME") { File.join(Dir.home, ".cache") }, "rclojure")
      end
      dir unless dir.empty?
    rescue ArgumentError
      nil
    end

    def self.digest
      @digest ||= Digest::SHA256.new.tap do |sha|
        sha << RUBY_VERSION << RUBY_REVISION << RUBY_PLATFORM << VERSION
        SOURCES.each { |path| sha << path << File.binread(path) }
      end.hexdigest
    end

    # The Runtime whose vars are being loaded (see Var._load).
    def self.loading_runtime
      Thread.current[:rclojure_loading_runtime]
    end

    def initialize(dir)
      @dir = dir
      @path = File.join(dir, "core-#{CoreCache.digest}.bin")
    end

    # [next gensym id, code, constants] cached for runtime, where code is
    # a lambda to call with constants; nil when there's no usable cache.
    def load(runtime)
      data = File.binread(@path)
      Thread.current[:rclojure_loading_runtime] = runtime
      next_id, binary, constants = Marshal.load(data, ->(object) { object.is_a?(::String) ? object.freeze : object })
      [next_id, RubyVM::InstructionSequence.load_from_binary(binary).eval, constants]
    rescue SystemCallError, TypeError, ArgumentError, RuntimeError
      nil
    ensure
      Thread.current[:rclojure_loading_runtime] = nil
    end

    # Writes the cache for units, the [source, constants] Compiler#compile
    # returned for each of core's forms, replacing caches for other
    # digests. Fails silently: the cache is only an optimization.
    def store(next_id, units)
      calls = units.each_with_index.map { |(source, _), i| "(#{source}).call(constants[#{i}])" }
      code = RubyVM::InstructionSequence.compile("->(constants) {\n#{calls.join("\n")}\n}", "(rclojure core)")
      data = Marshal.dump([next_id, code.to_binary, units.map(&:last)])
      FileUtils.mkdir_p(@dir)
      Dir[File.join(@dir, "core-*.bin")].each { |old| File.delete(old) }
      temp = "#{@path}.#{Process.pid}.tmp"
      File.binwrite(temp, data)
      File.rename(temp, @path)
    rescue SystemCallError, TypeError
      nil
    end
  end
end
