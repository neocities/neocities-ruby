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
  spec.extensions    = ['ext/mkrf_conf.rb']
  spec.required_ruby_version = '>3.0.0'

  spec.add_dependency 'tty-table',           '~> 0.12', '= 0.12.0'
  spec.add_dependency 'tty-prompt',          '~> 0.23', '= 0.23.1'
  spec.add_dependency 'pastel',              '~> 0.8',  '= 0.8.0'
  spec.add_dependency 'http',                '~> 5.3',  '>= 5.3.1'
  spec.add_dependency 'rake',                '~> 13',   '>= 13.3.0'
  spec.add_dependency 'whirly',              '~> 0.3',  '>= 0.3.0'
end
