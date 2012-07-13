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
    if uri
      @uri = uri.to_s.chomp
    else
      service = self.class.to_s.split('::').last.downcase
      service_uri = eval("$#{service}[:uri]")
      bad_request_error "$#{service}[:uri] variable not set. Please set $#{service}[:uri] or use an explicit uri as first constructor argument " unless service_uri
      @uri = File.join service_uri, SecureRandom.uuid
    end
    append RDF.type, eval("RDF::OT."+self.class.to_s.split('::').last)
    append RDF::DC.date, DateTime.now
    @subjectid = subjectid
  end

  # Object metadata 
  # @return [Hash] Object metadata
  def metadata 
    # return plain strings instead of RDF objects
    @rdf.to_hash[RDF::URI.new(@uri)].inject({}) { |h, (predicate, values)| h[predicate.to_s] = values.collect{|v| v.to_s}; h }
  end

  # Metadata values 
  # @param [String] Predicate URI
  # @return [Array, String] Predicate value(s)
  def [](predicate)
    return nil if metadata[predicate.to_s].nil?
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
  def get wait=true
    response = RestClientWrapper.get(@uri,{},{:accept => "text/plain", :subjectid => @subjectid})
    if URI.task?(response) and wait
      t = OpenTox::Task.new(uri).wait
      response = RestClientWrapper.get(t.resultURI,{},{:accept => "text/plain", :subjectid => @subjectid})
    end
    parse_ntriples response
  #rescue # fall back to rdfxml
    #parse_rdfxml RestClientWrapper.get(@uri,{},{:accept => "application/rdf+xml", :subjectid => @subjectid})
  end

  # Post object to webservice
  def post service_uri, wait=true
    uri = RestClientWrapper.post service_uri, to_ntriples, { :content_type => "text/plain", :subjectid => @subjectid}
    OpenTox::Task.new(uri).wait if URI.task?(uri) and wait
  #rescue # fall back to rdfxml
    #RestClientWrapper.post service_uri, to_rdfxml, { :content_type => "application/rdf+xml", :subjectid => @subjectid}
  end

  # Save object at webservice
  def put wait=true
    append RDF::DC.modified, DateTime.now
    #begin
      RestClientWrapper.put @uri.to_s, self.to_ntriples, { :content_type => "text/plain", :subjectid => @subjectid}
    #rescue # fall back to rdfxml
      #RestClientWrapper.put @uri.to_s, self.to_rdfxml, { :content_type => "application/rdf+xml", :subjectid => @subjectid}
    #end
    OpenTox::Task.new(uri).wait if URI.task?(uri) and wait
  end

  # Delete object at webservice
  def delete 
    RestClientWrapper.delete(@uri.to_s,nil,{:subjectid => @subjectid})
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

  def to_turtle # redefine to use prefixes (not supported by RDF::Writer)
    prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"}
    ['OT', 'DC', 'XSD', 'OLO'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
    turtle = RDF::N3::Writer.for(:turtle).buffer(:prefixes => prefixes)  do |writer|
      @rdf.each{|statement| writer << statement}
    end
  end

  {:title => RDF::DC.title, :dexcription => RDF::DC.description}.each do |method,predicate|
    send :define_method, method do 
      self.[](predicate) 
    end
    send :define_method, "#{method}=" do |value|
      self.[]=(predicate,value) 
    end
  end

  # create default OpenTox classes
  CLASSES.each do |klass|
    c = Class.new do
      include OpenTox
      #extend OpenTox::ClassMethods

      def self.all service_uri, subjectid=nil
        uris = RestClientWrapper.get(service_uri, {}, :accept => 'text/uri-list').split("\n").compact
        uris.collect{|uri| self.new(uri, subjectid)}
      end
    end
    OpenTox.const_set klass,c
  end

end

