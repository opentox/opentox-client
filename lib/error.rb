# adding additional fields to Exception class to format errors according to OT-API

class RuntimeError
  attr_accessor :http_code
  @http_code = 500
end

module OpenTox

  # Errors received from RestClientWrapper calls
  class RestError < RuntimeError
    attr_accessor :request, :response, :cause
    def initialize args
      @request = args[:request]
      @response = args[:response]
      args[:http_code] ? @http_code = args[:http_code] : @http_code = @response.code if @response
      @cause = args[:cause]
      msg = args.to_yaml
      $logger.error msg
      super msg
    end
  end

  # Errors rescued from task blocks
  class TaskError < RuntimeError
    attr_reader :error, :actor, :report
    def initialize error, actor=nil
      @error = error
      @actor = actor
      @report = ErrorReport.create error, actor
      msg = "\nActor: \"#{actor}\"\n"
      msg += @error.to_yaml
      #$logger.error msg
      super msg
    end
  end

  class ErrorReport
    
    # TODO replace params with URIs (errorCause -> OT.errorCause)
    attr_reader :message, :actor, :errorCause, :http_code, :errorDetails, :errorType

    private
    def initialize( http_code, erroType, message, actor, errorCause, rest_params=nil, backtrace=nil )
      @http_code = http_code
      #@errorType = erroType
      @message = message
      @actor = actor
      @errorCause = errorCause
      @rest_params = rest_params
      @backtrace = backtrace
    end
    
    public
    # creates a error report object, from an ruby-exception object
    # @param [Exception] error
    # @param [String] actor, URI of the call that cause the error
    def self.create( error, actor )
      rest_params = error.request if error.respond_to? :request
      backtrace = error.backtrace.short_backtrace if error.respond_to? :backtrace and error.backtrace #if CONFIG[:backtrace]
      error.respond_to?(:http_code) ? http_code = error.http_code : http_code = 500
      error.respond_to?(:cause) ? cause = error.cause : cause = 'Unknown'
      ErrorReport.new( http_code, error.class.to_s, error.message, actor, cause, rest_params, backtrace )
    end
    
    def self.from_rdf(rdf)
      metadata = OpenTox::Parser::Owl.from_rdf( rdf, OT.ErrorReport ).metadata
      ErrorReport.new(metadata[OT.statusCode], metadata[OT.errorCode], metadata[OT.message], metadata[OT.actor], metadata[OT.errorCause])
    end
    
    # overwrite sorting to make easier readable
    def to_yaml_properties
       p = super
       p = ( p - ["@backtrace"]) + ["@backtrace"] if @backtrace
       p = ( p - ["@errorCause"]) + ["@errorCause"] if @errorCause
       p
    end
    
    def rdf_content()
      c = {
        RDF.type => [OT.ErrorReport],
        OT.statusCode => @http_code,
        OT.message => @message,
        OT.actor => @actor,
        OT.errorCode => @errorType,
      }
      c[OT.errorCause] = @errorCause.rdf_content if @errorCause
      c
    end
    
    # TODO: use rdf.rb
    def to_rdfxml
      s = Serializer::Owl.new
      s.add_resource(CONFIG[:services]["opentox-task"]+"/tmpId/ErrorReport/tmpId", OT.errorReport, rdf_content)
      s.to_rdfxml
    end

  end
end

class Array
  def short_backtrace
    short = []
    each do |c|
      break if c =~ /sinatra\/base/
      short << c
    end
    short.join("\n")
  end
end
