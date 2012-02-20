require 'rubygems'
require "bundler/setup"
require 'rdf'
require 'rdf/raptor'
require "rest-client"
require 'uri'
require 'yaml'
require 'logger'
require File.join(File.dirname(__FILE__),"error.rb")
require File.join(File.dirname(__FILE__),"otlogger.rb") # avoid require conflicts with logger
require File.join(File.dirname(__FILE__),"opentox.rb")
require File.join(File.dirname(__FILE__),"task.rb")
require File.join(File.dirname(__FILE__),"compound.rb")
#require File.join(File.dirname(__FILE__),"dataset.rb")
