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

  def parameters
    params = {}
    query = RDF::Query.new({
      :parameter => {
        RDF.type  => RDF::OT.Parameter,
        :property => :value,
      }
    })
    query.execute(@rdf).each do |solution|
      params[solution.parameter] = {} unless params[solution.parameter] 
      params[solution.parameter][solution.property.to_s] = solution.value.to_s
    end
    params.values
  end

  def parameters=(parameters)
    parameters.each do |param|
      p_node = RDF::Node.new
      @rdf << [RDF::URI.new(@uri), RDF::OT.parameters, p_node]
      @rdf << [p_node, RDF.type, RDF::OT.Parameter]
      param.each{ |p,o| @rdf << [p_node, p, o] }
    end
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
  def get mime_type="text/plain"
    response = RestClientWrapper.get(@uri,{},{:accept => mime_type, :subjectid => @subjectid})
    if URI.task?(response)
      wait_for_task response
      response = RestClientWrapper.get(t.resultURI,{},{:accept => mime_type, :subjectid => @subjectid})
    end
    parse_ntriples response if mime_type == "text/plain"
    parse_rdfxml response if mime_type == "application/rdf+xml"
  end

  # Post object to webservice
  def post service_uri, wait=true
    # TODO: RDFXML
    uri = RestClientWrapper.post service_uri, to_ntriples, { :content_type => "text/plain", :subjectid => @subjectid}
    wait_for_task uri if wait
  end

  # Save object at webservice
  def put wait=true
    # TODO: RDFXML
    append RDF::DC.modified, DateTime.now
    uri = RestClientWrapper.put @uri.to_s, self.to_ntriples, { :content_type => "text/plain", :subjectid => @subjectid}
    wait_for_task uri if wait
  end

  # Delete object at webservice
  def delete 
    RestClientWrapper.delete(@uri.to_s,nil,{:subjectid => @subjectid})
  end

  def wait_for_task uri
    if URI.task?(uri) 
      t = OpenTox::Task.new uri
      t.wait
      if t.completed?
        uri = t.resultURI
      else
        #TODO raise correct error
        internal_server_error "Task #{uri} failed with #{$!.inspect}"
      end
    end
    uri
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

  {
    :title => RDF::DC.title,
    :dexcription => RDF::DC.description,
    :type => RDF.type
  }.each do |method,predicate|
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

      def self.all service_uri, subjectid=nil
        uris = RestClientWrapper.get(service_uri, {}, :accept => 'text/uri-list').split("\n").compact
        uris.collect{|uri| self.new(uri, subjectid)}
      end
    end
    OpenTox.const_set klass,c
  end

end

