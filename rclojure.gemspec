require_relative "lib/rclojure/version"

Gem::Specification.new do |spec|
  spec.name          = "rclojure"
  spec.version       = RClojure::VERSION
  spec.authors       = ["Édipo Féderle"]
  spec.summary       = "A Clojure dialect hosted on Ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files         = Dir["lib/**/*.rb", "bin/*", "README.md"]
  spec.bindir        = "bin"
  spec.executables   = ["rclj"]
  spec.require_paths = ["lib"]
end
