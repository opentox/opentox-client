# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "opentox-client/version"

Gem::Specification.new do |s|
  s.name        = "opentox-client"
  s.version     = Opentox::Client::VERSION
  s.authors     = ["Christoph Helma, Martin Guetlein, Andreas Maunz, Micha Rautenberg, David Vorgrimmler"]
  s.email       = ["helma@in-silico.ch"]
  s.homepage    = "http://github.com/opentox/opentox-client"
  s.summary     = %q{Ruby wrapper for the OpenTox REST API}
  s.description = %q{Ruby wrapper for the OpenTox REST API (http://www.opentox.org)}

  s.rubyforge_project = "opentox-client"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  s.add_runtime_dependency "rest-client"
  s.add_runtime_dependency "rdf"
  s.add_runtime_dependency "rdf-raptor"
end
