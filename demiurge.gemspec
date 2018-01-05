# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'demiurge/version'

Gem::Specification.new do |spec|
  spec.name          = "demiurge"
  spec.version       = Demiurge::VERSION
  spec.authors       = ["Noah Gibbs"]
  spec.email         = ["the.codefolio.guy@gmail.com"]

  spec.summary       = %q{A creator and manager for game rules and state.}
  spec.description   = %q{A creator and manager for game rules and state, separate from displaying and controlling the game. The idea is that a primarily-simulation game may be written using Ruby rules and a connection to the Demiurge process, while control and display are handled separately. This approach is primarily useful for 'simulation' games rather than fast-reflex 'twitch' games.}
  spec.homepage      = "https://github.com/noahgibbs/demiurge"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "multi_json", "~>1.12"
  spec.add_runtime_dependency "tmx", "~>0.1.5"

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "yard", "~> 0.9"
end
