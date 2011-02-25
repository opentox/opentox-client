# set default environment
ENV['RACK_ENV'] = 'production' unless ENV['RACK_ENV']

# load/setup configuration
basedir = File.join(ENV['HOME'], ".opentox")
config_dir = File.join(basedir, "config")
config_file = File.join(config_dir, "#{ENV['RACK_ENV']}.yaml")
user_file = File.join(config_dir, "users.yaml")

TMP_DIR = File.join(basedir, "tmp")
LOG_DIR = File.join(basedir, "log")

if File.exist?(config_file)
	CONFIG = YAML.load_file(config_file)
  raise "could not load config, config file: "+config_file.to_s unless CONFIG
else
	FileUtils.mkdir_p TMP_DIR
	FileUtils.mkdir_p LOG_DIR
	FileUtils.mkdir_p config_dir
	FileUtils.cp(File.join(File.dirname(__FILE__), 'templates/config.yaml'), config_file)
	puts "Please edit #{config_file} and restart your application."
	exit
end

# database
if CONFIG[:database]
	['dm-core', 'dm-serializer', 'dm-timestamps', 'dm-types', 'dm-migrations', 'dm-validations' ].each{|lib| require lib }
=begin
=end
	case CONFIG[:database][:adapter]
	when /sqlite/i
		db_dir = File.join(basedir, "db")
		FileUtils.mkdir_p db_dir
		DataMapper::setup(:default, "sqlite3://#{db_dir}/opentox.sqlite3")
	#when /yaml/i
		#db_dir = File.join(basedir, "db")
		#FileUtils.mkdir_p db_dir
		#DataMapper::setup(:default, {:adapter => "yaml", :directory => 'db'})
	else
		DataMapper.setup(:default, { 
				:adapter  => CONFIG[:database][:adapter],
				:database => CONFIG[:database][:database],
				:username => CONFIG[:database][:username],
				:password => CONFIG[:database][:password],
				:host     => CONFIG[:database][:host]})
	end
		#db_dir = File.join(basedir, "db")
		#FileUtils.mkdir_p db_dir
	#DataMapper::setup(:in_memory, "in_memory")
   #require 'redis'

       #DataMapper.setup(:default, {:adapter  => "redis"})

	#DataMapper::Model.raise_on_save_failure = true
end

# load mail settings for error messages
load File.join config_dir,"mail.rb" if File.exists?(File.join config_dir,"mail.rb")

logfile = "#{LOG_DIR}/#{ENV["RACK_ENV"]}.log"
#LOGGER = OTLogger.new(logfile,'daily') # daily rotation
LOGGER = OTLogger.new(logfile) # no rotation
LOGGER.formatter = Logger::Formatter.new #this is neccessary to restore the formating in case active-record is loaded
if CONFIG[:logger] and CONFIG[:logger] == "debug"
	LOGGER.level = Logger::DEBUG
else
	LOGGER.level = Logger::WARN 
end

# Regular expressions for parsing classification data
TRUE_REGEXP = /^(true|active|1|1.0|tox)$/i
FALSE_REGEXP = /^(false|inactive|0|0.0|low tox)$/i

# Task durations
DEFAULT_TASK_MAX_DURATION = 36000
#EXTERNAL_TASK_MAX_DURATION = 36000

# OWL Namespaces
class OwlNamespace

  attr_accessor :uri
  def initialize(uri)
    @uri = uri
  end

  def [](property)
    @uri+property.to_s
  end

  def type # for RDF.type
    "#{@uri}type"
  end

  def method_missing(property)
    @uri+property.to_s
  end

end

AA_SERVER = CONFIG[:authorization] ? (CONFIG[:authorization][:server] ? CONFIG[:authorization][:server] : nil) : nil
CONFIG[:authorization][:authenticate_request] = [""] unless CONFIG[:authorization][:authenticate_request]
CONFIG[:authorization][:authorize_request] =  [""] unless CONFIG[:authorization][:authorize_request]
CONFIG[:authorization][:free_request] =  [""] unless CONFIG[:authorization][:free_request]

RDF = OwlNamespace.new 'http://www.w3.org/1999/02/22-rdf-syntax-ns#'
OWL = OwlNamespace.new 'http://www.w3.org/2002/07/owl#'
DC =  OwlNamespace.new 'http://purl.org/dc/elements/1.1/'
OT =  OwlNamespace.new 'http://www.opentox.org/api/1.1#'
OTA =  OwlNamespace.new 'http://www.opentox.org/algorithmTypes.owl#'
XSD = OwlNamespace.new 'http://www.w3.org/2001/XMLSchema#'

