require_relative "rclojure/version"
require_relative "rclojure/errors"
require_relative "rclojure/types"
require_relative "rclojure/reader"
require_relative "rclojure/printer"

module RClojure
  def self.read_string(source)
    Reader.read_string(source)
  end

  def self.pr_str(value)
    Printer.pr_str(value)
  end
end
