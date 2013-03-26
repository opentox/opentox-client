# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG

module OpenTox
  #include RDF CH: leads to namespace clashes with URI class

  attr_reader :uri, :subjectid
  attr_writer :metadata, :parameters

  # Ruby interface

  # Create a new OpenTox object 
  # @param [optional,String] URI
  # @param [optional,String] subjectid
  # @return [OpenTox] OpenTox object
  def initialize uri=nil, subjectid=nil
    @rdf = RDF::Graph.new
    @subjectid = subjectid
    @metadata = {}
    @parameters = []
    uri ? @uri = uri.to_s.chomp : @uri = File.join(service_uri, SecureRandom.uuid)
  end

  # Object metadata (lazy loading)
  # @return [Hash] Object metadata
  def metadata force_update=false
    if (@metadata.empty? or force_update) and URI.accessible? @uri
      get if @rdf.empty? or force_update 
      # return values as plain strings instead of RDF objects
      @metadata = @rdf.to_hash[RDF::URI.new(@uri)].inject({}) { |h, (predicate, values)| h[predicate] = values.collect{|v| v.to_s}; h }
    end
    @metadata
  end

  # Metadata values 
  # @param [String] Predicate URI
  # @return [Array, String] Predicate value(s)
  def [](predicate)
    return nil if metadata[predicate].nil?
    metadata[predicate].size == 1 ? metadata[predicate].first : metadata[predicate]
  end

  # Set a metadata entry
  # @param [String] Predicate URI
  # @param [Array, String] Predicate value(s)
  def []=(predicate,values)
    @metadata[predicate] = [values].flatten
  end

  def parameters force_update=false
    if (@parameters.empty? or force_update) and URI.accessible? @uri
      get if @rdf.empty? or force_update
      params = {}
      query = RDF::Query.new({
        :parameter => {
          RDF.type  => RDF::OT.Parameter,
          :property => :value,
        }
      })
      query.execute(@rdf).each do |solution|
        params[solution.parameter] = {} unless params[solution.parameter] 
        params[solution.parameter][solution.property] = solution.value
      end
      @parameters = params.values
    end
    @parameters
  end

  def parameter_value title
    @parameters.collect{|p| p[RDF::OT.paramValue] if p[RDF::DC.title] == title}.compact.first
  end

  # Get object from webservice
  def get mime_type="text/plain"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'text/plain' (default) or 'application/rdf+xml'." unless mime_type == "text/plain" or mime_type == "application/rdf+xml"
    response = RestClientWrapper.get(@uri,{},{:accept => mime_type, :subjectid => @subjectid})
    if URI.task?(response)
      uri = wait_for_task response
      response = RestClientWrapper.get(uri,{},{:accept => mime_type, :subjectid => @subjectid})
    end
    parse_ntriples response if mime_type == "text/plain"
    parse_rdfxml response if mime_type == "application/rdf+xml"
  end

  # Post object to webservice (append to object), rarely useful and deprecated 
  def post wait=true, mime_type="text/plain"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'text/plain' (default) or 'application/rdf+xml'." unless mime_type == "text/plain" or mime_type == "application/rdf+xml"
    case mime_type
    when 'text/plain'
      body = self.to_ntriples
    when 'application/rdf+xml'
      body = self.to_rdfxml
    end
    uri = RestClientWrapper.post @uri.to_s, body, { :content_type => mime_type, :subjectid => @subjectid}
    wait ? wait_for_task(uri) : uri
  end

  # Save object at webservice (replace or create object)
  def put wait=true, mime_type="text/plain"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'text/plain' (default) or 'application/rdf+xml'." unless mime_type == "text/plain" or mime_type == "application/rdf+xml"
    case mime_type
    when 'text/plain'
      body = self.to_ntriples
    when 'application/rdf+xml'
      body = self.to_rdfxml
    end
    uri = RestClientWrapper.put @uri.to_s, body, { :content_type => mime_type, :subjectid => @subjectid}
    wait ? wait_for_task(uri) : uri
  end

  # Delete object at webservice
  def delete 
    RestClientWrapper.delete(@uri.to_s,nil,{:subjectid => @subjectid})
  end

  def service_uri
    self.class.service_uri
  end

  def create_rdf
    @rdf = RDF::Graph.new
    @metadata[RDF.type] ||= eval("RDF::OT."+self.class.to_s.split('::').last)
    @metadata[RDF::DC.date] ||= DateTime.now
    @metadata.each do |predicate,values|
      [values].flatten.each { |value| @rdf << [RDF::URI.new(@uri), predicate, value] }
    end
    @parameters.each do |parameter|
      p_node = RDF::Node.new
      @rdf << [RDF::URI.new(@uri), RDF::OT.parameters, p_node]
      @rdf << [p_node, RDF.type, RDF::OT.Parameter]
      parameter.each { |k,v| @rdf << [p_node, k, v] }
    end
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
      create_rdf
      RDF::Writer.for(format).buffer(:encoding => Encoding::ASCII) do |writer|
        @rdf.each{|statement| writer << statement}
      end
    end
  end

  def to_turtle # redefined to use prefixes (not supported by RDF::Writer)
    prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"}
    ['OT', 'DC', 'XSD', 'OLO'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
    create_rdf
    RDF::N3::Writer.for(:turtle).buffer(:prefixes => prefixes)  do |writer|
      @rdf.each{|statement| writer << statement}
    end
  end

  def to_html
    to_turtle.to_html
  end

  { :title => RDF::DC.title, :dexcription => RDF::DC.description, :type => RDF.type }.each do |method,predicate|
    send :define_method, method do 
      self.[](predicate) 
    end
    send :define_method, "#{method}=" do |value|
      self.[]=(predicate,value) 
    end
  end

  # create default OpenTox classes with class methods
  CLASSES.each do |klass|
    c = Class.new do
      include OpenTox

      def self.all subjectid=nil
        uris = RestClientWrapper.get(service_uri, {}, :accept => 'text/uri-list').split("\n").compact
        uris.collect{|uri| self.new(uri, subjectid)}
      end

      def self.find uri, subjectid=nil
        URI.accessible?(uri) ? self.new(uri, subjectid) : nil
      end

      def self.create metadata, subjectid=nil 
        object = self.new nil, subjectid
        object.metadata = metadata
        object.put
        object
      end

      def self.find_or_create metadata, subjectid=nil
        sparql = "SELECT DISTINCT ?s WHERE { "
        metadata.each do |predicate,objects|
          unless [RDF::DC.date,RDF::DC.modified,RDF::DC.description].include? predicate # remove dates and description (strange characters in description may lead to SPARQL errors)
            if objects.is_a? String
              URI.valid?(objects) ? o = "<#{objects}>" : o = "'''#{objects}'''" 
              sparql << "?s <#{predicate}> #{o}. " 
            elsif objects.is_a? Array
              objects.each do |object|
                URI.valid?(object) ? o = "<#{object}>" : o = "'#{object}'" 
                sparql << "?s <#{predicate}> #{o}. " 
              end
            end
          end
        end
        sparql <<  "}"
        uris = RestClientWrapper.get(service_uri,{:query => sparql},{:accept => "text/uri-list", :subjectid => @subjectid}).split("\n")
        if uris.empty?
          self.create metadata, subjectid
        else
          self.new uris.first
        end
      end

      def self.service_uri
        service = self.to_s.split('::').last.downcase
        eval("$#{service}[:uri]")
      rescue
        bad_request_error "$#{service}[:uri] variable not set. Please set $#{service}[:uri] or use an explicit uri as first constructor argument "
      end

    end
    OpenTox.const_set klass,c
  end

end

