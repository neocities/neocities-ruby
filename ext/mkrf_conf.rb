require 'rubygems'
require 'rubygems/command'
require 'rubygems/dependency_installer'
begin
  Gem::Command.build_args = ARGV
  rescue NoMethodError
end
inst = Gem::DependencyInstaller.new
begin
  if Gem.win_platform?
    inst.install 'openssl-win-root', '~> 1.1'
  end
  rescue
    exit(1)
end

f = File.open(File.join(File.dirname(__FILE__), "Rakefile"), "w")   # create dummy rakefile to indicate success
f.write("task :default\n")
f.close
