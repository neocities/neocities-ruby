# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'neocities/version'

Gem::Specification.new do |spec|
  spec.name          = "neocities"
  spec.version       = Neocities::VERSION
  spec.authors       = ["Kyle Drake"]
  spec.email         = ["kyle@kyledrake.net"]
  spec.summary       = %q{Library for the NeoCities.org API}
  spec.homepage      = "https://neocities.org"
  spec.license       = "MIT"
  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
end
