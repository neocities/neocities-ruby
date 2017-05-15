# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'neocities/version'

Gem::Specification.new do |spec|
  spec.name          = "neocities"
  spec.version       = Neocities::VERSION
  spec.authors       = ["Kyle Drake"]
  spec.email         = ["contact@neocities.org"]
  spec.summary       = %q{Neocities.org CLI and API client}
  spec.homepage      = "https://neocities.org"
  spec.license       = "MIT"
  spec.files         = `git ls-files | grep -Ev '^(test)'`.split("\n")
  spec.executables   = ['neocities']
  spec.test_files    = spec.files.grep(%r{^(tests)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'tty-table',     '~> 0.8', '>= 0.8.0'
  spec.add_dependency 'tty-prompt',    '~> 0.12', '>= 0.12.0'
  spec.add_dependency 'pastel',        '~> 0.7', '>= 0.7.1'
  spec.add_dependency 'http',          '~> 2.2', '>= 2.2.2'
  spec.add_dependency 'buff-ignore',   '~> 1.2'

#  spec.add_development_dependency      'rake', '~> 10.0'
#  spec.add_development_dependency      'faker'
#  spec.add_development_dependency      'minitest'
#  spec.add_development_dependency      'minitest-reporters'
#  spec.add_development_dependency      'rack-test'
#  spec.add_development_dependency      'mocha'
#  spec.add_development_dependency      'webmock'
#  spec.add_development_dependency      'simplecov'
end
