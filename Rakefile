require "bundler/gem_tasks"

=begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "opentox-client"
    gem.summary = %Q{Ruby wrapper for the OpenTox REST API}
    gem.description = %Q{Ruby wrapper for the OpenTox REST API (http://www.opentox.org)}
    gem.email = "helma@in-silico.ch"
    gem.homepage = "http://github.com/opentox/opentox-ruby-minimal"
    gem.authors = ["Christoph Helma, Martin Guetlein, Andreas Maunz, Micha Rautenberg, David Vorgrimmler"]
    # dependencies with versions
    gem.add_dependency "rest-client"
    gem.add_dependency "rdf"
    gem.add_dependency "rdf-raptor"
    gem.add_development_dependency 'jeweler'
    gem.files =  FileList["[A-Z]*", "{bin,generators,lib,test}/**/*", 'lib/jeweler/templates/.gitignore']
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: sudo gem install jeweler"
=end

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.libs << 'lib'
  t.test_files = FileList['test/*.rb']
  t.verbose = true
end

