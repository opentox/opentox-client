require 'open4'

# add additional fields to Exception class to format errors according to OT-API
class RuntimeError
  attr_accessor :http_code, :uri
  def initialize message, uri=nil
    super message
    @uri = uri
    @http_code ||= 500
    $logger.error "\n"+self.report.to_turtle
  end

  def report
    # TODO: remove kludge for old task services
    OpenTox::ErrorReport.new(@http_code, self)
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
  
  # Errors received from RestClientWrapper calls
  class RestCallError < Error
    attr_accessor :request#, :response
    def initialize message, request, uri
    #def initialize request, response, message
      @request = request
      #@response = response
      super 502, message, uri
    end
  end

  # TODO: create reports directly from errors, requires modified task service
  class ErrorReport
    def initialize http_code, error
      @http_code = http_code
      @report = {}
      @report[RDF::OT.actor] = error.uri.to_s
      @report[RDF::OT.message] = error.message.to_s
      @report[RDF::OT.statusCode] = @http_code 
      @report[RDF::OT.errorCode] = error.class.to_s

      # cut backtrace
      backtrace = caller.collect{|line| line unless line =~ /#{File.dirname(__FILE__)}/}.compact
      cut_index = backtrace.find_index{|line| line.match /sinatra|minitest/}
      cut_index ||= backtrace.size
      cut_index -= 1
      cut_index = backtrace.size-1 if cut_index < 0
      @report[RDF::OT.errorDetails] = backtrace[0..cut_index].join("\n")
      @report[RDF::OT.errorDetails] += "REST paramenters:\n#{error.request.args.inspect}" if defined? error.request
      #@report[RDF::OT.message] += "\n" + error.response.body.to_s if defined? error.response
      # TODO fix Error cause
      # should point to another errorReport, but errorReports do not have URIs
      # create a separate service?
      #report[RDF::OT.errorCause] = @report if defined?(@report) 
    end

    # define to_ and self.from_ methods for various rdf formats
    RDF_FORMATS.each do |format|

      send :define_method, "to_#{format}".to_sym do
        rdf = RDF::Writer.for(format).buffer do |writer|
          # TODO: not used for turtle
          # http://rdf.rubyforge.org/RDF/Writer.html#
          writer.prefix :ot, RDF::URI('http://www.opentox.org/api/1.2#')
          writer.prefix :ot1_1, RDF::URI('http://www.opentox.org/api/1.1#')
          subject = RDF::Node.new
          @report.each do |predicate,object|
            writer << [subject, predicate, object] if object
          end
        end
        rdf
      end

=begin
      define_singleton_method "from_#{format}".to_sym do |rdf|
        report = ErrorReport.new
        RDF::Reader.for(format).new(rdf) do |reader|
          reader.each_statement{ |statement| report.rdf << statement }
        end
        report
      end
=end
    end
  end
end
