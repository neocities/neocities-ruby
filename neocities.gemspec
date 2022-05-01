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

  spec.add_dependency 'tty-table',           '~> 0.10', '= 0.10.0'
  spec.add_dependency 'tty-prompt',          '~> 0.12', '= 0.12.0'
  spec.add_dependency 'pastel',              '~> 0.7',  '= 0.7.2'
  spec.add_dependency 'httpclient-fixcerts', '~> 2.8',  '>= 2.8.5'
  spec.add_dependency 'rake',                '~> 12.3',  '>= 12.3.1'
end
