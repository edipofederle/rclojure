require "digest"
require "fileutils"

module RClojure
  # Caches the analyzed nodes of core.clj, so a Runtime can evaluate them
  # without reading and macroexpanding the source (most of its startup
  # time). The cache file's name is a digest of everything that shapes
  # the nodes: core.clj, rclojure's Ruby sources and the Ruby version.
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
        sha << RUBY_VERSION << VERSION
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

    # [next gensym id, nodes] cached for runtime, or nil when there's no
    # usable cache.
    def load(runtime)
      data = File.binread(@path)
      Thread.current[:rclojure_loading_runtime] = runtime
      Marshal.load(data, ->(object) { object.is_a?(::String) ? object.freeze : object })
    rescue SystemCallError, TypeError, ArgumentError
      nil
    ensure
      Thread.current[:rclojure_loading_runtime] = nil
    end

    # Writes the cache, replacing caches for other digests. Fails silently:
    # the cache is only an optimization.
    def store(next_id, nodes)
      data = Marshal.dump([next_id, nodes])
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
