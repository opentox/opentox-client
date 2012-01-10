require "./parser.rb"
require "./rest_client_wrapper.rb"
require "./error.rb"

SERVICES = ["Compound", "Feature", "Dataset", "Algorithm", "Model", "Validation", "Task"]

module OpenTox

  attr_accessor :subjectid, :uri
  attr_writer :metadata

  # Initialize OpenTox object with optional subjectid
  # @param [optional, String] subjectid
  def initialize uri=nil, subjectid=nil
    @uri = uri
    @subjectid = subjectid
  end

  def metadata
    @metadata ||= Parser::Owl::Generic.from_rdf get(:accept => "application/rdf+xml")
  end

  # REST API
  # returns OpenTox::WrapperResult, not OpenTox objects

  # perfoms a GET REST call
  # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
  # per default: waits for Task to finish and returns result URI of Task
  # @param [optional,Hash] headers contains params like accept-header
  # @param [wait,Boolean] wait set to false to NOT wait for task if result is task
  # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
  def get headers={}, wait=true 
    headers[:subjectid] = @subjectid
    RestClientWrapper.get(@uri, headers, nil, wait).chomp
  end

  # performs a POST REST call
  # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
  # per default: waits for Task to finish and returns result URI of Task
  # @param [optional,String] payload data posted to the service
  # @param [optional,Hash] headers contains params like accept-header
  # @param [wait,Boolean] wait set to false to NOT wait for task if result is task
  # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
  def post payload=nil, headers={}, wait=true 
    headers[:subjectid] = @subjectid
    RestClientWrapper.post(@uri, payload, headers, nil, wait).chomp
  end

  # performs a PUT REST call
  # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
  # @param [optional,String] payload data put to the service
  # @param [optional,Hash] headers contains params like accept-header
  # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
  def put payload=nil, headers={} 
    headers[:subjectid] = @subjectid
    RestClientWrapper.put(@uri, payload, headers).chomp
  end

  # performs a DELETE REST call
  # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
  # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
  def delete 
    RestClientWrapper.delete(@uri,:subjectid => @subjectid)
  end

  # Tools

  # Get OWL-DL representation in RDF/XML format
  # @return [application/rdf+xml] RDF/XML representation
  def to_rdfxml
    s = Serializer::Owl.new
    s.add_metadata(@uri,@metadata)
    s.to_rdfxml
  end

  def uri_available?
    url = URI.parse(@uri)
    #TODO: move subjectid to header
    subjectidstr = @subjectid ? "?subjectid=#{CGI.escape @subjectid}" : ""
    Net::HTTP.start(url.host, url.port) do |http|
      return http.head("#{url.request_uri}#{subjectidstr}").code == "200"
    end
  end

  # create default classes
  SERVICES.each { |s| eval "class #{s}; include OpenTox; end" }

  module Collection

    include OpenTox

    def find 
      uri_available? ? object_class.new(@uri, @subjectid) : nil
    end

    def create metadata
      object_class.new post(service_uri, metadata.to_rdfxml, { :content_type => 'application/rdf+xml', :subjectid => subjectid}).to_s.chomp, @subject_id 
    end

    # Get all objects from a service
    # @return [Array] List of available Objects
    def all
      get(:accept => "text/uri-list").to_s.split(/\n/).collect{|uri| object_class.new uri,@subjectid}
    end

    def save object
      object_class.new post(object.to_rdfxml, :content_type => 'application/rdf+xml').to_s, @subjectid
    end

    def object_class
      eval self.class.to_s.sub(/::Collection/,'')
    end

    # create collection classes
    SERVICES.each { |s| eval "class #{s}; include Collection; end" }

  end

end

