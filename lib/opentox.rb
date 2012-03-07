#TODO: switch services to 1.2
RDF::OT =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.2#'
RDF::OT1 =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.1#'
RDF::OTA =  RDF::Vocabulary.new 'http://www.opentox.org/algorithmTypes.owl#'

SERVICES = ["Compound", "Feature", "Dataset", "Algorithm", "Model", "Validation", "Task", "Investigation"]

# Regular expressions for parsing classification data
TRUE_REGEXP = /^(true|active|1|1.0|tox|activating|carcinogen|mutagenic)$/i
FALSE_REGEXP = /^(false|inactive|0|0.0|low tox|deactivating|non-carcinogen|non-mutagenic)$/i

# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG

module OpenTox

  attr_accessor :subjectid, :uri, :response
  attr_writer :metadata

  def initialize uri=nil, subjectid=nil
    @uri = uri.chomp
    @subjectid = subjectid
  end

  # Ruby interface

  def metadata reload=true
    if reload or @metadata.empty?
      @metadata = {}
      kind_of?(OpenTox::Dataset) ? uri = File.join(@uri,"metadata") : uri = @uri
      RDF::Reader.for(:rdfxml).new( RestClientWrapper.get(uri) ) do |reader|
        reader.each_statement do |statement|
          @metadata[statement.predicate] = statement.object if statement.subject == @uri
        end
      end
    end
    @metadata
  end

  def save
    post self.to_rdfxml, { :content_type => 'application/rdf+xml'}
  end

  def to_rdfxml
    rdf = RDF::Writer.for(:rdfxml).buffer do |writer|
      @metadata.each { |p,o| writer << RDF::Statement.new(RDF::URI.new(@uri), p, o) }
    end
    rdf
  end

  # REST API
  def get headers={}
    headers[:subjectid] ||= @subjectid
    headers[:accept] ||= 'application/rdf+xml'
    @response = RestClientWrapper.get @uri, {}, headers
  end

  def post payload={}, headers={}
    headers[:subjectid] ||= @subjectid
    headers[:accept] ||= 'application/rdf+xml'
    @response = RestClientWrapper.post(@uri.to_s, payload, headers)
  end

  def put payload={}, headers={} 
    headers[:subjectid] ||= @subjectid
    headers[:accept] ||= 'application/rdf+xml'
    @response = RestClientWrapper.put(@uri.to_s, payload, headers)
  end

  def delete headers={}
    headers[:subjectid] ||= @subjectid
    @response = RestClientWrapper.delete(@uri.to_s,nil,nil,headers)
  end

  # class methods
  module ClassMethods

    def create service_uri, subjectid=nil
      uri = RestClientWrapper.post(service_uri, {}, :subjectid => subjectid).chomp
      subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")
    end

    def from_file service_uri, filename, subjectid=nil
      file = File.new filename
      uri = RestClientWrapper.post(service_uri, {:file => file}, {:subjectid => subjectid, :content_type => file.mime_type, :accept => "text/uri-list"})
      puts uri
    end

    def all service_uri, subjectid=nil
      uris = RestClientWrapper.get(service_uri, {}, :accept => 'text/uri-list').split("\n").compact
      uris.collect{|uri| subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")}
    end

  end

  # create default OpenTox classes
  SERVICES.each do |klass|
    c = Class.new do
      include OpenTox
      extend OpenTox::ClassMethods
    end
    OpenTox.const_set klass,c
  end

end

