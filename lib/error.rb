require 'open4'

# add additional fields to Exception class to format errors according to OT-API
class RuntimeError
  attr_accessor :http_code, :uri
  def initialize message, uri=nil
    super message
    @uri = uri
    @http_code ||= 500
    @rdf = RDF::Graph.new
    subject = RDF::Node.new
    @rdf << [subject, RDF.type, RDF::OT.ErrorReport]
    @rdf << [subject, RDF::OT.actor, @uri.to_s]
    @rdf << [subject, RDF::OT.message, message.to_s]
    @rdf << [subject, RDF::OT.statusCode, @http_code]
    @rdf << [subject, RDF::OT.errorCode, self.class.to_s]
    @rdf << [subject, RDF::OT.errorCause, short_backtrace]
    $logger.error("\n"+self.to_turtle)
  end

  def short_backtrace
    backtrace = caller.collect{|line| line unless line =~ /#{File.dirname(__FILE__)}/}.compact
    cut_index = backtrace.find_index{|line| line.match /sinatra|minitest/}
    cut_index ||= backtrace.size
    cut_index -= 1
    cut_index = backtrace.size-1 if cut_index < 0
    backtrace[0..cut_index].join("\n")
  end

  RDF_FORMATS.each do |format|
    # rdf serialization methods for all formats e.g. to_rdfxml
    send :define_method, "to_#{format}".to_sym do
      RDF::Writer.for(format).buffer do |writer|
        @rdf.each{|statement| writer << statement}
      end
    end
  end

  def to_turtle # redefine to use prefixes (not supported by RDF::Writer)
    prefixes = {:rdf => "http://www.w3.org/1999/02/22-rdf-syntax-ns#"}
    ['OT', 'DC', 'XSD', 'OLO'].each{|p| prefixes[p.downcase.to_sym] = eval("RDF::#{p}.to_s") }
    RDF::N3::Writer.for(:turtle).buffer(:prefixes => prefixes)  do |writer|
      @rdf.each{|statement| writer << statement}
    end
  end

end

module OpenTox

  class Error < RuntimeError
    
    def initialize code, message, uri=nil
      @http_code = code
      super message, uri
    end
  end

  # OpenTox errors
  {
    "BadRequestError" => 400,
    "NotAuthorizedError" => 401,
    "NotFoundError" => 404,
    "LockedError" => 423,
    "InternalServerError" => 500,
    "NotImplementedError" => 501,
    "RestCallError" => 501,
    "ServiceUnavailableError" => 503,
    "TimeOutError" => 504,
  }.each do |klass,code|
    # create error classes 
    c = Class.new Error do
      define_method :initialize do |message, uri=nil|
        super code, message, uri
      end
    end
    OpenTox.const_set klass,c
    
    # define global methods for raising errors, eg. bad_request_error
    Object.send(:define_method, klass.underscore.to_sym) do |message,uri=nil|
      raise c.new(message, uri)
    end
  end
  
end
