require 'open4'

# add additional fields to Exception class to format errors according to OT-API
class RuntimeError
  attr_accessor :http_code, :uri
  def initialize message, uri=nil
    super message
    @uri = uri
    @http_code ||= 500
    $logger.error "\n"+self.to_turtle
  end

  # define to_ methods for all RuntimeErrors and various rdf formats
  RDF_FORMATS.each do |format|

    send :define_method, "to_#{format}".to_sym do
      rdf = RDF::Writer.for(format).buffer do |writer|
        # TODO: not used for turtle
        # http://rdf.rubyforge.org/RDF/Writer.html#
        writer.prefix :ot, RDF::URI('http://www.opentox.org/api/1.2#')
        writer.prefix :ot1_1, RDF::URI('http://www.opentox.org/api/1.1#')
        subject = RDF::Node.new
        writer << [subject, RDF.type, RDF::OT.ErrorReport]
        writer << [subject, RDF::OT.actor, @uri.to_s]
        writer << [subject, RDF::OT.message, message.to_s]
        writer << [subject, RDF::OT.statusCode, @http_code]
        writer << [subject, RDF::OT.errorCode, self.class.to_s]

        # cut backtrace
        backtrace = caller.collect{|line| line unless line =~ /#{File.dirname(__FILE__)}/}.compact
        cut_index = backtrace.find_index{|line| line.match /sinatra|minitest/}
        cut_index ||= backtrace.size
        cut_index -= 1
        cut_index = backtrace.size-1 if cut_index < 0
        details = backtrace[0..cut_index].join("\n")
        writer << [subject, RDF::OT.errorCause, details]
      end
      rdf
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
      raise c, message, uri
    end
  end
  
end
