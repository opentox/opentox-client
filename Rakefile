require 'rubygems'
require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "opentox-ruby-minimal"
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
end

=begin
require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/*_test.rb'
  test.verbose = true
end

begin
  require 'rcov/rcovtask'
  Rcov::RcovTask.new do |test|
    test.libs << 'test'
    test.pattern = 'test/**/*_test.rb'
    test.verbose = true
  end
rescue LoadError
  task :rcov do
    abort "RCov is not available. In order to run rcov, you must: sudo gem install spicycode-rcov"
  end
end

task :test => :check_dependencies

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  if File.exist?('VERSION')
    version = File.read('VERSION')
  else
    version = ""
  end

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "opentox-ruby-minimal #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
=end
