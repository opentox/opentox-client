require 'rubygems'
require "bundler/setup"
require 'rdf'
require 'rdf/raptor'
require 'rdf/n3'
require "rest-client"
require 'uri'
require 'yaml'
require 'json'
require 'logger'
require "securerandom"

# define constants and global variables
#TODO: switch services to 1.2
RDF::OT =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.2#'
RDF::OT1 =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.1#'
RDF::OTA =  RDF::Vocabulary.new 'http://www.opentox.org/algorithmTypes.owl#'
RDF::OLO =  RDF::Vocabulary.new 'http://purl.org/ontology/olo/core#'

CLASSES = ["Generic", "Compound", "Feature", "Dataset", "Algorithm", "Model", "Validation", "Task", "Investigation"]
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
  "dataset.rb",
  "model.rb",
].each{ |f| require File.join(File.dirname(__FILE__),f) }

