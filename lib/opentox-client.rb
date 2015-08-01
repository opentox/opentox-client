require 'rubygems'
require "bundler/setup"
require "rest-client"
require 'yaml'
require 'json'
require 'logger'
require 'mongoid'

# TODO store development/test, validation, production in separate databases
ENV["MONGOID_ENV"] = "development"
Mongoid.load!("#{ENV['HOME']}/.opentox/config/mongoid.yml")

CLASSES = ["Compound", "Feature", "Dataset"]#, "Validation", "Task", "Investigation"]
#CLASSES = ["Feature", "Dataset", "Validation", "Task", "Investigation"]

# Regular expressions for parsing classification data
TRUE_REGEXP = /^(true|active|1|1.0|tox|activating|carcinogen|mutagenic)$/i
FALSE_REGEXP = /^(false|inactive|0|0.0|low tox|deactivating|non-carcinogen|non-mutagenic)$/i

[
  "overwrite.rb",
  "rest-client-wrapper.rb", 
  "error.rb",
  #"authorization.rb", 
  #"policy.rb", 
  #"otlogger.rb", 
  "opentox.rb",
  #"task.rb",
  "compound.rb",
  "feature.rb",
  #"data_entry.rb",
  "dataset.rb",
  #"algorithm.rb",
  #"model.rb",
  "validation.rb"
].each{ |f| require_relative f }

#if defined?($aa) and $aa[:uri] 
#  OpenTox::Authorization.authenticate($aa[:user],$aa[:password])
#  unauthorized_error "Failed to authenticate user \"#{$aa[:user]}\"." unless OpenTox::Authorization.is_token_valid(OpenTox::RestClientWrapper.subjectid)
#end

# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = Logger.new STDOUT #OTLogger.new(STDOUT) # STDERR did not work on my development machine (CH)
$logger.level = Logger::DEBUG
#Mongo::Logger.logger = $logger
Mongo::Logger.level = Logger::WARN 
$mongo = Mongo::Client.new('mongodb://127.0.0.1:27017/opentox')
$gridfs = $mongo.database.fs
Mongoid.logger.level = Logger::WARN
Mongoid.logger = $logger
