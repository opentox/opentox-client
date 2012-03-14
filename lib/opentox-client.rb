require 'rubygems'
require "bundler/setup"
require 'rdf'
require 'rdf/raptor'
require "rest-client"
require 'uri'
require 'yaml'
require 'logger'

# define constants and global variables
#TODO: switch services to 1.2
RDF::OT =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.2#'
RDF::OT1 =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.1#'
RDF::OTA =  RDF::Vocabulary.new 'http://www.opentox.org/algorithmTypes.owl#'

#CLASSES = ["Compound", "Feature", "Dataset", "Algorithm", "Model", "Validation", "Task", "ErrorReport", "Investigation"]
CLASSES = ["Generic", "Compound", "Feature", "Dataset", "Algorithm", "Model", "Validation", "Task", "Investigation"]
RDF_FORMATS = [:rdfxml,:ntriples,:turtle]
$default_rdf = "application/rdf+xml"

# Regular expressions for parsing classification data
TRUE_REGEXP = /^(true|active|1|1.0|tox|activating|carcinogen|mutagenic)$/i
FALSE_REGEXP = /^(false|inactive|0|0.0|low tox|deactivating|non-carcinogen|non-mutagenic)$/i

require File.join(File.dirname(__FILE__),"overwrite.rb")
require File.join(File.dirname(__FILE__),"error.rb")
require File.join(File.dirname(__FILE__),"rest-client-wrapper.rb") 
require File.join(File.dirname(__FILE__),"otlogger.rb") # avoid require conflicts with logger
require File.join(File.dirname(__FILE__),"opentox.rb")
require File.join(File.dirname(__FILE__),"task.rb")
require File.join(File.dirname(__FILE__),"compound.rb")
#require File.join(File.dirname(__FILE__),"dataset.rb")
