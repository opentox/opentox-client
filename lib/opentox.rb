# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG

module OpenTox

  attr_accessor :uri, :subjectid, :rdf, :response

  # Ruby interface

  # Create a new OpenTox object (does not load data from service)
  # @param [optional,String] URI
  # @param [optional,String] subjectid
  # @return [OpenTox] OpenTox object
  def initialize uri=nil, subjectid=nil
    @uri = uri.to_s.chomp
    @subjectid = subjectid
    @rdf = RDF::Graph.new
  end

  # Load metadata from service
  def pull
    kind_of?(OpenTox::Dataset) ? uri = File.join(@uri,"metadata") : uri = @uri
    # TODO generic method for all formats
    parse_rdfxml RestClientWrapper.get(uri,{},{:accept => $default_rdf, :subjectid => @subjectid})
  end

  # Get object metadata 
  # @return [Hash] Metadata
  def metadata 
    pull if @rdf.empty?
    metadata = {}
    @rdf.query([RDF::URI.new(@uri),nil,nil]).collect do |statement|
      metadata[statement.predicate] ||= []
      metadata[statement.predicate] << statement.object
    end
    metadata.each{|k,v| metadata[k] = v.first if v.size == 1}
  end

  # Get metadata values 
  # @param [RDF] Key from RDF Vocabularies
  # @return [Array] Values for supplied key
  def [](key)
    pull if @rdf.empty?
    result = @rdf.query([RDF::URI.new(@uri),key,nil]).collect{|statement| statement.object}
    result.size == 1 ? result.first : result
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
      subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")
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

