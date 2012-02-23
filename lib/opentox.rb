#TODO: switch services to 1.2
RDF::OT =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.2#'
RDF::OT1 =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.1#'
RDF::OTA =  RDF::Vocabulary.new 'http://www.opentox.org/algorithmTypes.owl#'
SERVICES = ["Compound", "Feature", "Dataset", "Algorithm", "Model", "Validation", "Task", "Investigation"]

class String
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end

module URI

  def self.task? uri
    uri =~ /task/ and URI.valid? uri
  end
  
  def self.dataset? uri, subjectid=nil
    uri =~ /dataset/ and URI.accessible? uri, subjectid=nil
  end
 
  def self.model? uri, subjectid=nil
    uri =~ /model/ and URI.accessible? uri, subjectid=nil
  end

  def self.accessible? uri, subjectid=nil
    Net::HTTP.get_response(URI.parse(uri))
    true
  rescue
    false
  end

  def self.valid? uri
    u = URI::parse(uri)
    u.scheme!=nil and u.host!=nil
  rescue URI::InvalidURIError
    false
  end
end

# defaults to stderr, may be changed to file output
$logger = OTLogger.new(STDERR) # no rotation
$logger.level = Logger::DEBUG

module OpenTox

  attr_accessor :subjectid, :uri, :response
  attr_writer :metadata

  def initialize uri=nil, subjectid=nil
    @uri = uri.chomp
    @subjectid = subjectid
  end

  # Ruby interface


  # override to read all error codes
  def metadata reload=true
    if reload
      @metadata = {}
      # ignore error codes from Task services (may contain eg 500 which causes exceptions in RestClient and RDF::Reader
      RestClient.get(@uri) do |response, request, result, &block|
        $logger.warn "#{@uri} returned #{result}" unless response.code == 200 or response.code == 202 or URI.task? @uri
        RDF::Reader.for(:rdfxml).new(response) do |reader|
          reader.each_statement do |statement|
            @metadata[statement.predicate] = statement.object if statement.subject == @uri
          end
        end
      end
    end
    @metadata
  end

  def save
    rdf = RDF::Writer.for(:rdfxml).buffer do |writer|
      @metadata.each { |p,o| writer << RDF::Statement.new(RDF::URI.new(@uri), p, o) }
    end
    post rdf, { :content_type => 'application/rdf+xml'}
  end

  # REST API
  def get params={}
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.get @uri, params
  end

  def post payload={}, params={}
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.post(@uri.to_s, payload, params)
    begin
      @response.to_s.to_object
    rescue
      @response
    end
  end

  def put payload={}, params={} 
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.put(@uri.to_s, payload, params)
  end

  def delete params={}
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.delete(@uri.to_s,:subjectid => @subjectid)
  end

  # class methods
  module ClassMethods

    def create service_uri, subjectid=nil
      uri = RestClient.post(service_uri, {}, :subjectid => subjectid).chomp
      subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")
    end

    def from_file service_uri, file, subjectid=nil
      RestClient.post(service_uri, :file => File.new(file), :subjectid => subjectid).chomp.to_object
    end

    def all service_uri, subjectid=nil
      uris = RestClient.get(service_uri, {:accept => 'text/uri-list'}).split("\n").compact
      uris.collect{|uri| subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")}
    end

  end

  # create default classes
  SERVICES.each do |s|
    eval "class #{s}
      include OpenTox
      extend OpenTox::ClassMethods
    end"
  end

end

