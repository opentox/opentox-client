# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG
#$logger.level = ENV['RACK_ENV'] == 'production' ? Logger::ERROR : Logger::DEBUG
 
module OpenTox
  #include RDF CH: leads to namespace clashes with URI class

  attr_reader :uri
  attr_writer :metadata, :parameters

  # Ruby interface

  # Create a new OpenTox object 
  # @param uri [optional,String] URI
  # @return [OpenTox] OpenTox object
  def initialize uri=nil
    @rdf = RDF::Graph.new
    @metadata = {}
    @parameters = []
    uri ? @uri = uri.to_s.chomp : @uri = File.join(service_uri, SecureRandom.uuid)
  end

  # Object metadata (lazy loading)
  # @return [Hash] Object metadata
  def metadata force_update=false
    if (@metadata.nil? or @metadata.empty? or force_update) and URI.accessible? @uri
      get if @rdf.nil? or @rdf.empty? or force_update 
      # return values as plain strings instead of RDF objects
      @metadata = @rdf.to_hash[RDF::URI.new(@uri)].inject({}) { |h, (predicate, values)| h[predicate] = values.collect{|v| v.to_s}; h }
    end
    @metadata
  end

  # Metadata values 
  # @param predicate [String] Predicate URI
  # @return [Array, String] Predicate value(s)
  def [](predicate)
    return nil if metadata[predicate].nil?
    metadata[predicate].size == 1 ? metadata[predicate].first : metadata[predicate]
  end

  # Set a metadata entry
  # @param predicate [String] Predicate URI
  # @param values [Array, String] Predicate value(s)
  def []=(predicate,values)
    @metadata[predicate] = [values].flatten
  end

  # Object parameters (lazy loading)
  # {http://opentox.org/dev/apis/api-1.2/interfaces OpenTox API}
  # @return [Hash] Object parameters
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
  
  # Parameter value 
  # @param [String] title 
  # @return [String] value
  def parameter_value title
    @parameters.collect{|p| p[RDF::OT.paramValue] if p[RDF::DC.title] == title}.compact.first
  end

  # Get object from webservice
  # @param [String,optional] mime_type
  def get mime_type="text/plain"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'text/plain' (default) or 'application/rdf+xml'." unless mime_type == "text/plain" or mime_type == "application/rdf+xml"
    response = RestClientWrapper.get(@uri,{},{:accept => mime_type})
    if URI.task?(response)
      uri = wait_for_task response
      response = RestClientWrapper.get(uri,{},{:accept => mime_type})
    end
    parse_ntriples response if mime_type == "text/plain"
    parse_rdfxml response if mime_type == "application/rdf+xml"
  end

  # Post object to webservice (append to object), rarely useful and deprecated 
  # @deprecated
  def post wait=true, mime_type="text/plain"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'text/plain' (default) or 'application/rdf+xml'." unless mime_type == "text/plain" or mime_type == "application/rdf+xml"
    case mime_type
    when 'text/plain'
      body = self.to_ntriples
    when 'application/rdf+xml'
      body = self.to_rdfxml
    end
    #Authorization.check_policy(@uri) if $aa[:uri]
    uri = RestClientWrapper.post @uri.to_s, body, { :content_type => mime_type}
    wait ? wait_for_task(uri) : uri
  end

  # Save object at webservice (replace or create object)
  def put wait=true, mime_type="text/plain"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'text/plain' (default) or 'application/rdf+xml'." unless mime_type == "text/plain" or mime_type == "application/rdf+xml"
    @metadata[RDF::OT.created_at] = DateTime.now unless URI.accessible? @uri
    #@metadata[RDF::DC.modified] = DateTime.now
    case mime_type
    when 'text/plain'
      body = self.to_ntriples
    when 'application/rdf+xml'
      body = self.to_rdfxml
    end
    uri = RestClientWrapper.put @uri, body, { :content_type => mime_type}
    wait ? wait_for_task(uri) : uri
  end

  # Delete object at webservice
  def delete 
    RestClientWrapper.delete(@uri)
    #Authorization.delete_policies_from_uri(@uri) if $aa[:uri]
  end

  def service_uri
    self.class.service_uri
  end
  
  def create_rdf
    #$logger.debug "#{eval("RDF::OT."+self.class.to_s.split('::').last)}\n"
    @rdf = RDF::Graph.new
    # DG: since model is no self.class anymore 
    @metadata[RDF.type] ||= (eval("RDF::OT."+self.class.to_s.split('::').last) =~ /Lazar|Generic/) ? RDF::URI.new(RDF::OT.Model) : RDF::URI.new(eval("RDF::OT."+self.class.to_s.split('::').last))
    #@metadata[RDF.type] ||= RDF::URI.new(eval("RDF::OT."+self.class.to_s.split('::').last))
    @metadata[RDF::DC.date] ||= DateTime.now
    # DG: uri in object should be in brackets, otherwise query for uri-list ignores the object.
    # see: http://www.w3.org/TR/rdf-testcases/#sec-uri-encoding
    @metadata.each do |predicate,values|
      [values].flatten.each{ |value| @rdf << [RDF::URI.new(@uri), predicate, (URI.valid?(value) ? RDF::URI.new(value) : value)] unless value.nil? }
    end
    @parameters.each do |parameter|
      p_node = RDF::Node.new
      @rdf << [RDF::URI.new(@uri), RDF::OT.parameters, p_node]
      @rdf << [p_node, RDF.type, RDF::OT.Parameter]
      parameter.each { |k,v| @rdf << [p_node, k, v] unless v.nil?}
    end
  end
  
  # as defined in opentox-client.rb
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
      # if encoding is used iteration is necessary
      # see: http://rubydoc.info/github/ruby-rdf/rdf/RDF/NTriples/Writer
      RDF::Writer.for(format).buffer(:encoding => Encoding::ASCII) do |writer|
        @rdf.each_statement do |statement|
          writer << statement
        end
      end
    end
  end
  
  # @return [String] converts object to turtle-string
  def to_turtle # redefined to use prefixes (not supported by RDF::Writer)
    prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"}
    ['OT', 'DC', 'XSD', 'OLO'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
    create_rdf
    RDF::Turtle::Writer.for(:turtle).buffer(:prefixes => prefixes)  do |writer|
      writer << @rdf
    end
  end

  # @return [String] converts OpenTox object into html document (by first converting it to a string)
  def to_html
    to_turtle.to_html
  end

  # short access for metadata keys title, description and type
  { :title => RDF::DC.title, :description => RDF::DC.description, :type => RDF.type }.each do |method,predicate|
    send :define_method, method do 
      self.[](predicate) 
    end
    send :define_method, "#{method}=" do |value|
      self.[]=(predicate,value) 
    end
  end

  # define class methods within module
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def service_uri
      service = self.to_s.split('::')[1].downcase
      eval("$#{service}[:uri]")
    rescue
      bad_request_error "$#{service}[:uri] variable not set. Please set $#{service}[:uri] or use an explicit uri as first constructor argument "
    end
    def subjectid
      RestClientWrapper.subjectid
    end
    def subjectid=(subjectid)
      RestClientWrapper.subjectid = subjectid
    end
  end

  # create default OpenTox classes with class methods
  # (defined in opentox-client.rb)
  CLASSES.each do |klass|
    c = Class.new do
      include OpenTox

      def self.all 
        uris = RestClientWrapper.get(service_uri, {},{:accept => 'text/uri-list'}).split("\n").compact
        uris.collect{|uri| self.new(uri)}
      end

      #@example fetching a model
      #  OpenTox::Model.find(<model-uri>) -> model-object
      def self.find uri
        URI.accessible?(uri) ? self.new(uri) : nil
      end

      def self.create metadata
        object = self.new 
        object.metadata = metadata
        object.put
        object
      end

      def self.find_or_create metadata
        t = Time.now
        sparql = "SELECT DISTINCT ?s WHERE { "
        # flatten 3.level arrays in objects
        metadata.each{|p,o| o.flatten! if o.is_a? Array}
        metadata.each do |predicate,objects|
          unless [RDF::DC.date,RDF::DC.modified,RDF::DC.description].include? predicate # remove dates and description (strange characters in description may lead to SPARQL errors)
            if objects.is_a? String
              #URI.valid?(objects) ? o = "<#{objects}>" : o = "'''#{objects}'''" #DG: do not understand this quotation
              URI.valid?(objects) ? o = "<#{objects}>" : o = "\"#{objects}\""
              sparql << "?s <#{predicate}> #{o}. " 
            elsif objects.is_a? Array
              objects.each do |object|
                #URI.valid?(object) ? o = "<#{object}>" : o = "'#{object}'" #DG: do not understand this quotation
                URI.valid?(object) ? o = "<#{object}>" : o = "\"#{object}\"" 
                sparql << "?s <#{predicate}> #{o}. " 
              end
            end
          end
        end
        sparql <<  "}"
        puts "Create SPARQL: #{Time.now-t}"
        t = Time.new
        uris = RestClientWrapper.get(service_uri,{:query => sparql},{:accept => "text/uri-list"}).split("\n")
        puts "Query: #{Time.now-t}"
        t = Time.new
        if uris.empty?
          f=self.create metadata
          puts "Create: #{Time.now-t}"
          f
        else
          f=self.new uris.first
          puts "Found: #{Time.now-t}"
          f
        end
      end
    end
    OpenTox.const_set klass,c
  end

end

