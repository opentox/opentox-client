require File.join(File.dirname(__FILE__),"lib","opentox-client.rb")
require "bundler/gem_tasks"
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.test_files = FileList['test/*.rb']
  t.verbose = true
end

