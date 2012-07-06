# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG

module OpenTox

  attr_accessor :uri, :subjectid, :rdf

  # Ruby interface

  # Create a new OpenTox object (does not load data from service)
  # @param [optional,String] URI
  # @param [optional,String] subjectid
  # @return [OpenTox] OpenTox object
  def initialize uri=nil, subjectid=nil
    @rdf = RDF::Graph.new
    uri ?  @uri = uri.to_s.chomp : @uri = RDF::Node.uuid.to_s
    append RDF.type, eval("RDF::OT."+self.class.to_s.split('::').last)
    append RDF::DC.date, DateTime.now
    @subjectid = subjectid
  end

  # Object metadata 
  # @return [Hash] Object metadata
  def metadata 
    # return plain strings instead of RDF objects
    #puts @rdf.to_hash
    @rdf.to_hash[RDF::URI.new(@uri)].inject({}) { |h, (predicate, values)| h[predicate.to_s] = values.collect{|v| v.to_s}; h }
  end

  # Metadata values 
  # @param [String] Predicate URI
  # @return [Array, String] Predicate value(s)
  def [](predicate)
    metadata[predicate.to_s].size == 1 ? metadata[predicate.to_s].first : metadata[predicate.to_s]
  end

  # Set object metadata
  # @param [String] Predicate URI
  # @param [Array, String] Predicate value(s)
  def []=(predicate,values)
    @rdf.delete [RDF::URI.new(@uri.to_s),RDF::URI.new(predicate.to_s),nil] 
    append predicate.to_s, values
  end

  # Append object metadata
  # @param [String] Predicate URI
  # @param [Array, String] Predicate value(s)
  def append(predicate,values)
    uri = RDF::URI.new @uri
    predicate = RDF::URI.new predicate
    [values].flatten.each { |value| @rdf << [uri, predicate, value] }
  end

  # Get object from webservice
  def get 
    parse_ntriples RestClientWrapper.get(@uri,{},{:accept => "text/plain", :subjectid => @subjectid})
  rescue # fall back to rdfxml
    parse_rdfxml RestClientWrapper.get(@uri,{},{:accept => "application/rdf+xml", :subjectid => @subjectid})
  end

  # Post object to webservice
  def post service_uri
    RestClientWrapper.post service_uri, to_ntriples, { :content_type => "text/plain", :subjectid => @subjectid}
  rescue # fall back to rdfxml
    RestClientWrapper.post service_uri, to_rdfxml, { :content_type => "application/rdf+xml", :subjectid => @subjectid}
  end

  # Save object at webservice
  def put 
    append RDF::DC.modified, DateTime.now
    begin
      RestClientWrapper.put @uri.to_s, self.to_ntriples, { :content_type => "text/plain", :subjectid => @subjectid}
    rescue # fall back to rdfxml
      RestClientWrapper.put @uri.to_s, self.to_rdfxml, { :content_type => "application/rdf+xml", :subjectid => @subjectid}
    end
  end

  # Delete object at webservice
  def delete 
    @response = RestClientWrapper.delete(@uri.to_s,nil,{:subjectid => @subjectid})
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

  # class methods
  module ClassMethods

    def all service_uri, subjectid=nil
      uris = RestClientWrapper.get(service_uri, {}, :accept => 'text/uri-list').split("\n").compact
      uris.collect{|uri| URI.task?(service_uri) ? from_uri(uri, subjectid, false) : from_uri(uri, subjectid)}
    end

    def from_file service_uri, filename, subjectid=nil
      file = File.new filename
      # sdf files are incorrectly detected
      file.mime_type = "chemical/x-mdl-sdfile" if File.extname(filename) == ".sdf"
      from_uri RestClientWrapper.post(service_uri, {:file => file}, {:subjectid => subjectid, :content_type => file.mime_type, :accept => "text/uri-list"}), subjectid
    end

    private
    def from_uri uri, subjectid=nil, wait=true
        
      uri.chomp!
      # TODO add waiting task
      if URI.task?(uri) and wait
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

