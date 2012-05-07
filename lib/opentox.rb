# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG

module OpenTox

  attr_accessor :uri, :subjectid, :rdf, :response, :reload

  # Ruby interface

  # Create a new OpenTox object (does not load data from service)
  # @param [optional,String] URI
  # @param [optional,String] subjectid
  # @return [OpenTox] OpenTox object
  def initialize uri=nil, subjectid=nil
    @uri = uri.to_s.chomp
    @subjectid = subjectid
    @reload = true
    @rdf = RDF::Graph.new
  end

  # Load metadata from service
  def pull
    # TODO generic method for all formats
    parse_rdfxml RestClientWrapper.get(@uri,{},{:accept => $default_rdf, :subjectid => @subjectid})
  end

  # Get object metadata 
  # @return [Hash] Metadata
  def metadata 
    pull if @reload # force update
    @rdf.to_hash[RDF::URI.new(@uri)]
  end

  # Get metadata values 
  # @param [RDF] Key from RDF Vocabularies
  # @return [Array] Values for supplied key
  def [](key)
    pull if @reload # force update
    result = @rdf.query([RDF::URI.new(@uri),key,nil]).collect{|statement| statement.object}
    # TODO: convert to OpenTox objects??
    return nil if result and result.empty?
    return result.first.to_s if result.size == 1 
    return result.collect{|r| r.to_s}
    result
  end

  # Save object at service
  def save
    #TODO: dynamic assignment
    post self.to_rdfxml, { :content_type => $default_rdf}
  end

  RDF_FORMATS.each do |format|

    # rdf parse methods for all formats e.g. parse_rdfxml
    send :define_method, "parse_#{format}".to_sym do |rdf|
      @rdf = RDF::Graph.new
      RDF::Reader.for(format).new(rdf) do |reader|
        reader.each_statement{ |statement| @rdf << statement }
      end
    end

    # rdf serialization methods for all formats e.g. to_rdfxml
    send :define_method, "to_#{format}".to_sym do
      rdf = RDF::Writer.for(format).buffer do |writer|
        @rdf.each{|statement| writer << statement}
      end
      rdf
    end
  end

  def to_yaml
    @rdf.to_hash.to_yaml
  end

  def to_json
    to_hash.to_json
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
    @response = RestClientWrapper.delete(@uri.to_s,nil,headers)
  end

  # class methods
  module ClassMethods

    def all service_uri, subjectid=nil
      uris = RestClientWrapper.get(service_uri, {}, :accept => 'text/uri-list').split("\n").compact
      uris.collect{|uri| URI.task?(service_uri) ? from_uri(uri, subjectid, false) : from_uri(uri, subjectid)}
    end

    def create service_uri, subjectid=nil
      #uri = uri(SecureRandom.uuid)
      uri = RestClientWrapper.post(service_uri, {}, {:accept => 'text/uri-list', :subjectid => subjectid})
      URI.task?(service_uri) ? from_uri(uri, subjectid, false) : from_uri(uri, subjectid)
    end

    def from_file service_uri, filename, subjectid=nil
      file = File.new filename
      from_uri RestClientWrapper.post(service_uri, {:file => file}, {:subjectid => subjectid, :content_type => file.mime_type, :accept => "text/uri-list"}), subjectid
    end

    private
    def from_uri uri, subjectid=nil, wait=true
        
      uri.chomp!
      # TODO add waiting task
      if URI.task? uri and wait
        t = OpenTox::Task.new(uri)
        t.wait
        uri = t.resultURI
      end

      # guess class from uri, this is potentially unsafe, but polling metadata from large uri lists is way too slow (and not all service provide RDF.type in their metadata)
      result = CLASSES.collect{|s| s if uri =~ /#{s.downcase}/}.compact
      if result.size == 1
        klass = result.first
      else
        klass = OpenTox::Generic.new(uri)[RDF.type]
        internal_server_error "Cannot determine class from URI '#{uri} (Candidate classes are #{result.inspect}) or matadata." unless klass
      end
      # initialize with/without subjectid
      subjectid ? eval("#{self}.new(\"#{uri}\", \"#{subjectid}\")") : eval("#{self}.new(\"#{uri}\")")
    end
  end

  # create default OpenTox classes
  CLASSES.each do |klass|
    c = Class.new do
      include OpenTox
      extend OpenTox::ClassMethods
    end
    OpenTox.const_set klass,c
  end

end

