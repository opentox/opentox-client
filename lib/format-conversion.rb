# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG

module OpenTox

  # Ruby interface

  attr_accessor :data

  # Create a new OpenTox object 
  # @param uri [optional,String] URI
  # @return [OpenTox] OpenTox object
  def initialize uri=nil
    @data = {}
    if uri
      @data[:uri] = uri.to_s.chomp
      get
    else
      @data[:uuid] = SecureRandom.uuid
      @data[:uri] = File.join(service_uri, @data[:uuid])
    end
  end

  # Object metadata (lazy loading)
  # @return [Hash] Object metadata
  def metadata force_update=false
    get #if (@metadata.nil? or @metadata.empty? or force_update) and URI.accessible? @uri
    @data
  end

  # Metadata values 
  # @param predicate [String] Predicate URI
  # @return [Array, String] Predicate value(s)
  def [](predicate)
    predicate = predicate.to_s
    return nil if metadata[predicate].nil?
    metadata[predicate].size == 1 ? metadata[predicate].first : metadata[predicate]
  end

  # Set a metadata entry
  # @param predicate [String] Predicate URI
  # @param values [Array, String] Predicate value(s)
  def []=(predicate,values)
    predicate = predicate.to_s
    @data[predicate] = [values].flatten
  end

=begin
  # Object parameters (lazy loading)
  # {http://opentox.org/dev/apis/api-1.2/interfaces OpenTox API}
  # @return [Hash] Object parameters
  def parameters force_update=false
    if (@parameters.empty? or force_update) and URI.accessible? @uri
      get #if @rdf.empty? or force_update
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
=end

  # Get object from webservice
  # @param [String,optional] mime_type
  def get mime_type="application/json"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'application/json' (default), 'text/plain' (ntriples) or mime_type == 'application/rdf+xml'."  unless mime_type == "application/json" or mime_type == "text/plain" or mime_type == "application/rdf+xml"
    p @data[:uri]
    response = RestClientWrapper.get(@data[:uri],{},{:accept => mime_type})
    if URI.task?(response)
      uri = wait_for_task response
      response = RestClientWrapper.get(uri,{},{:accept => mime_type})
      p uri
    end
    case mime_type
    when 'application/json'
      p response
      @data = JSON.parse(response) if response
    when "text/plain"
      parse_ntriples response 
    when "application/rdf+xml"
      parse_rdfxml response
    end
  end

=begin
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
=end

  # Save object at webservice (replace or create object)
  def put wait=true, mime_type="application/json"
    bad_request_error "Mime type #{mime_type} is not supported. Please use 'application/json' (default)."  unless mime_type == "application/json" or mime_type == "text/plain" or mime_type == "application/rdf+xml"
    @data[:created_at] = DateTime.now unless URI.accessible? @data[:uri]
    #@metadata[RDF::DC.modified] = DateTime.now
    @data[:uri] ? @data[:uri] = uri.to_s.chomp : @data[:uri] = File.join(service_uri, SecureRandom.uuid)
    case mime_type
    when 'text/plain'
      body = self.to_ntriples
    when 'application/rdf+xml'
      body = self.to_rdfxml
    when 'application/json'
      body = self.to_json
    end
    uri = RestClientWrapper.put @data[:uri], body, { :content_type => mime_type}
    wait ? wait_for_task(uri) : uri
  end

  # Delete object at webservice
  def delete 
    RestClientWrapper.delete(@data[:uri])
    #Authorization.delete_policies_from_uri(@data[:uri]) if $aa[:uri]
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
      [values].flatten.each{ |value| @rdf << [RDF::URI.new(@data[:uri]), predicate, (URI.valid?(value) ? RDF::URI.new(value) : value)] unless value.nil? }
    end
    @parameters.each do |parameter|
      p_node = RDF::Node.new
      @rdf << [RDF::URI.new(@data[:uri]), RDF::OT.parameters, p_node]
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
      # return values as plain strings instead of RDF objects
      @metadata = @rdf.to_hash[RDF::URI.new(@data[:uri])].inject({}) { |h, (predicate, values)| h[predicate] = values.collect{|v| v.to_s}; h }
    end

=begin
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
=end
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

  def to_json
    @data.to_json
  end

  # @return [String] converts OpenTox object into html document (by first converting it to a string)
  def to_html
    to_turtle.to_html
  end

  # short access for metadata keys title, description and type
  [ :title , :description , :type , :uri, :uuid ].each do |method|
    send :define_method, method do 
      self.data[method]
    end
    send :define_method, "#{method}=" do |value|
      self.data[method] = value
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
        object.data = metadata
        object.put
        object
      end

      def self.find_or_create metadata
        uris = RestClientWrapper.get(service_uri,{:query => @data},{:accept => "text/uri-list"}).split("\n")
        uris.empty? ? self.create(@data) : self.new(uris.first)
      end
    end
    OpenTox.const_set klass,c
  end

end

# from overwrite.rb
class String

  # encloses URI in text with with link tag
  # @return [String] new text with marked links
  def link_urls
    self.gsub(/(?i)http(s?):\/\/[^\r\n\s']*/, '<a href="\0">\0</a>')
  end

  # produces a html page for making web services browser friendly
  # format of text (=string params) is preserved (e.g. line breaks)
  # urls are marked as links
  #
  # @param related_links [optional,String] uri on related resources
  # @param description [optional,String] general info
  # @param png_image [optional,String] imagename
  # @return [String] html page
  def to_html(related_links=nil, description=nil, png_image=nil  )

    # TODO add title as parameter
    title = nil #$sinatra.to($sinatra.request.env['PATH_INFO'], :full) if $sinatra
    html = "<html><body>"
    html << "<title>"+title+"</title>" if title
    #html += "<img src=\""+OT_LOGO+"\"><\/img><body>"

    html << "<h3>Description</h3><pre><p>"+description.link_urls+"</p></pre>" if description
    html << "<h3>Related links</h3><pre><p>"+related_links.link_urls+"</p></pre>" if related_links
    html << "<h3>Content</h3>" if description || related_links
    html << "<pre><p style=\"padding:15px; border:10px solid \#C5C1E4\">"
    html << "<img src=\"data:image/png;base64,#{Base64.encode64(png_image)}\">\n" if png_image
    html << self.link_urls
    html << "</p></pre></body></html>"
    html
  end

  def uri?
    URI.valid?(self)
  end
end

module Kernel

=begin
  # overwrite backtick operator to catch system errors
  # Override raises an error if _cmd_ returns a non-zero exit status. CH: I do not understand this comment
  # Returns stdout if _cmd_ succeeds.  Note that these are simply concatenated; STDERR is not inline. CH: I do not understand this comment
  def ` cmd
    stdout, stderr = ''
    status = Open4::popen4(cmd) do |pid, stdin_stream, stdout_stream, stderr_stream|
      stdout = stdout_stream.read
      stderr = stderr_stream.read
    end
    internal_server_error "`" + cmd + "` failed.\n" + stdout + stderr unless status.success?
    return stdout
  rescue
    internal_server_error $!.message
  end
=end

  # @return [String] uri of task result, if task fails, an error according to task is raised
  def wait_for_task uri
    if URI.task?(uri)
      t = OpenTox::Task.new uri
      t.wait
      unless t.completed?
        error = OpenTox::RestClientWrapper.known_errors.select{|error| error[:code] == t.code}.first
        error_method = error ? error[:method] : :internal_server_error
        report = t.error_report
        error_message = report ? report[:message] : $!.message
        error_cause = report ? report[:errorCause] : nil 
        Object.send(error_method,error_message,t.uri,error_cause)
      end
      uri = t.resultURI
    end
    uri
  end


end
module URI

  def self.compound? uri
    uri =~ /compound/ and URI.valid? uri
  end

  def self.task? uri
    uri =~ /task/ and URI.valid? uri
  end

  def self.dataset? uri
    uri =~ /dataset/ and URI.accessible? uri
  end

  def self.model? uri
    uri =~ /model/ and URI.accessible? uri
  end

  def self.ssl? uri
    URI.parse(uri).instance_of? URI::HTTPS
  end

  # @return [Boolean] checks if resource exists by making a HEAD-request
  def self.accessible?(uri)
    parsed_uri = URI.parse(uri + (OpenTox::RestClientWrapper.subjectid ? "?subjectid=#{CGI.escape OpenTox::RestClientWrapper.subjectid}" : ""))
    http_code = URI.task?(uri) ? 600 : 400
    http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
    unless (URI.ssl? uri) == true
      http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
      request = Net::HTTP::Head.new(parsed_uri.request_uri)
      http.request(request).code.to_i < http_code
    else
      http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request = Net::HTTP::Head.new(parsed_uri.request_uri)
      http.request(request).code.to_i < http_code
    end
  rescue
    false
  end

  def self.valid? uri
    u = URI.parse(uri)
    u.scheme!=nil and u.host!=nil
  rescue URI::InvalidURIError
    false
  end

end
