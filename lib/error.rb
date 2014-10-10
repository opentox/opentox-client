require 'open4'

# add additional fields to Exception class to format errors according to OT-API
module OpenToxError
  attr_accessor :http_code, :uri, :error_cause
  def initialize(message=nil, uri=nil, cause=nil)
    message = message.to_s.gsub(/\A"|"\Z/, '') if message # remove quotes
    @error_cause = cause ? OpenToxError::cut_backtrace(cause) : short_backtrace
    
    super message
    #unless self.is_a? Errno::EAGAIN # avoid "Resource temporarily unavailable" errors
      @uri = uri.to_s.sub(%r{//.*:.*@},'//') # remove credentials from uri
      @http_code ||= 500
      @rdf = RDF::Graph.new
      subject = RDF::Node.new
      @rdf << [subject, RDF.type, RDF::OT.ErrorReport]
      @rdf << [subject, RDF::OT.actor, @uri]
      @rdf << [subject, RDF::OT.message, message.to_s]
      @rdf << [subject, RDF::OT.statusCode, @http_code]
      @rdf << [subject, RDF::OT.errorCode, self.class.to_s]
      @rdf << [subject, RDF::OT.errorCause, @error_cause]
      $logger.error("\n"+self.to_yaml) 
    #end
  end

  # this method defines what is used for to_yaml (override to skip large @rdf graph)
  def encode_with coder
    @rdf.each do |statement|
      coder[statement.predicate.fragment.to_s] = statement.object.to_s
    end
  end
  
  def self.cut_backtrace(trace)
    if trace.is_a?(Array)
      cut_index = trace.find_index{|line| line.match(/sinatra|minitest/)}
      cut_index ||= trace.size
      cut_index -= 1
      cut_index = trace.size-1 if cut_index < 0
      trace[0..cut_index].join("\n")
    else
      trace
    end
  end
  
  def short_backtrace
    backtrace = caller.collect{|line| line unless line =~ /#{File.dirname(__FILE__)}/}.compact
    OpenToxError::cut_backtrace(backtrace)
  end

  RDF_FORMATS.each do |format|
    # rdf serialization methods for all formats e.g. to_rdfxml
    send :define_method, "to_#{format}".to_sym do
      RDF::Writer.for(format).buffer do |writer|
        @rdf.each{|statement| writer << statement} if @rdf
      end
    end
  end

  def to_turtle # redefine to use prefixes (not supported by RDF::Writer)
    prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"}
    ['OT', 'DC', 'XSD', 'OLO'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
    RDF::Turtle::Writer.for(:turtle).buffer(:prefixes => prefixes)  do |writer|
      @rdf.each{|statement| writer << statement} if @rdf
    end
  end

end

class RuntimeError
#class StandardError
  include OpenToxError
end

# clutters log file with library errors
#class NoMethodError
  #include OpenToxError
#end

module OpenTox

  class Error < RuntimeError
    include OpenToxError
    
    def initialize(code, message=nil, uri=nil, cause=nil)
      @http_code = code
      super message, uri, cause
    end
  end

  # OpenTox errors
  RestClientWrapper.known_errors.each do |error|
    # create error classes 
    c = Class.new Error do
      define_method :initialize do |message=nil, uri=nil, cause=nil|
        super error[:code], message, uri, cause
      end
    end
    OpenTox.const_set error[:class],c
    
    # define global methods for raising errors, eg. bad_request_error
    Object.send(:define_method, error[:method]) do |message,uri=nil,cause=nil|
      raise c.new(message, uri, cause)
    end
  end
  
end
