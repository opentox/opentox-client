require 'rubygems'
require "bundler/setup"
require 'rdf'
require 'rdf/raptor'
require 'rdf/turtle'
require "rest-client"
require 'uri'
require 'yaml'
require 'json'
require 'logger'
require "securerandom"

default_config = File.join(ENV["HOME"],".opentox","config","default.rb")
client_config = File.join(ENV["HOME"],".opentox","config","opentox-client.rb")

puts "Could not find configuration files #{default_config} or #{client_config}" unless File.exist? default_config or File.exist? client_config
require default_config if File.exist? default_config
require client_config if File.exist? client_config

# define constants and global variables
RDF::OT =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.2#'
RDF::OT1 =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.1#'
RDF::OTA =  RDF::Vocabulary.new 'http://www.opentox.org/algorithmTypes.owl#'
RDF::OLO =  RDF::Vocabulary.new 'http://purl.org/ontology/olo/core#'
RDF::TB  = RDF::Vocabulary.new "http://onto.toxbank.net/api/"
RDF::ISA = RDF::Vocabulary.new "http://onto.toxbank.net/isa/"
RDF::OWL = RDF::Vocabulary.new "http://www.w3.org/2002/07/owl#"

CLASSES = ["Compound", "Feature", "Dataset", "Validation", "Task", "Investigation"]
RDF_FORMATS = [:rdfxml,:ntriples,:turtle]

# Regular expressions for parsing classification data
TRUE_REGEXP = /^(true|active|1|1.0|tox|activating|carcinogen|mutagenic)$/i
FALSE_REGEXP = /^(false|inactive|0|0.0|low tox|deactivating|non-carcinogen|non-mutagenic)$/i

[
  "overwrite.rb",
  "rest-client-wrapper.rb", 
  "error.rb",
  "authorization.rb", 
  "policy.rb", 
  "otlogger.rb", 
  "opentox.rb",
  "task.rb",
  "compound.rb",
  "feature.rb",
  "dataset.rb",
  "algorithm.rb",
  "model.rb",
  "validation.rb"
].each{ |f| require_relative f }

if defined?($aa) and $aa[:uri] 
  OpenTox::RestClientWrapper.subjectid = OpenTox::Authorization.authenticate($aa[:user],$aa[:password])
  unauthorized_error "Failed to authenticate user \"#{$aa[:user]}\"." unless OpenTox::Authorization.is_token_valid(OpenTox::RestClientWrapper.subjectid)
end

