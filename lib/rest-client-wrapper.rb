module OpenTox
  
  class RestClientWrapper
    
    attr_accessor :request, :response

    # REST methods 
    # Raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
    # Waits for Task to finish and returns result URI of Task per default
    # @param [String] destination URI
    # @param [optional,Hash|String] Payload data posted to the service
    # @param [optional,Hash] Headers with params like :accept, :content_type, :subjectid
    # @param [optional,OpenTox::Task] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @param [wait,Boolean] Set to false to NOT wait for task if result is a task
    # @return [RestClient::Response] REST call response 
    [:head,:get,:post,:put,:delete].each do |method|

      define_singleton_method method do |uri,payload={},headers={},waiting_task=nil, wait=true|
      
        # create request
        args={}
        args[:method] = method
        args[:url] = uri
        args[:timeout] = 600
        args[:payload] = payload
        headers.each{ |k,v| headers.delete(k) if v==nil } if headers #remove keys with empty values, as this can cause problems
        args[:headers] = headers 

        # check input 
        bad_request_error "Invalid URI: '#{uri}'" unless URI.valid? uri
        not_found_error "URI '#{uri}' not found." unless URI.accessible? uri
        bad_request_error "Headers are not a hash: #{headers.inspect}" unless headers==nil or headers.is_a?(Hash)
        # make sure that no header parameters are set in the payload
        [:accept,:content_type,:subjectid].each do |header|
          bad_request_error "#{header} should be submitted in the headers" if payload and payload.is_a?(Hash) and payload[header] 
        end
        #bad_request_error "waiting_task is not 'nil', OpenTox::SubTask or OpenTox::Task: #{waiting_task.class}" unless waiting_task.nil? or waiting_task.is_a?(OpenTox::Task) or waiting_task.is_a?(OpenTox::SubTask)

        # perform request
        @request = RestClient::Request.new(args)
        #begin
          # do not throw RestClient exceptions in order to create a @response object (needed for error reports) in every case
          @response = @request.execute { |response, request, result| return response }
          # ignore error codes from Task services (may return error codes >= 400 according to API, which causes exceptions in RestClient and RDF::Reader)
          raise OpenTox::RestCallError.new @request, @response, "Response code is #{@response.code}." unless @response.code < 400 or URI.task? uri
          #return @response if @response.code==200 or !wait

          # wait for task
          #while @response.code==201 or @response.code==202
            #@response = wait_for_task(@response, uri, waiting_task)
          #end
          @response
          
        #rescue
          #rest_error $!.message
        #end
      end
    end
    
=begin
    def wait_for_task( response, base_uri, waiting_task=nil )

      task = nil
      case @response.headers[:content_type]
      when /application\/rdf\+xml/
        # TODO: task uri from rdf
        #task = OpenTox::Task.from_rdfxml(@response)
        #task = OpenTox::Task.from_rdfxml(@response)
      when /text\/uri-list/
        rest_error "Uri list has more than one entry, should be a single task" if @response.split("\n").size > 1 #if uri list contains more then one uri, its not a task
        task = OpenTox::Task.new(@response.to_s.chomp) if URI.available? @response.to_s
      else
        rest_error "Unknown content-type for task : '"+@response.headers[:content_type].to_s+"'"+" base-uri: "+base_uri.to_s+" content: "+@response[0..200].to_s
      end
      
      task.wait waiting_task
      unless task.completed? # maybe task was cancelled / error
        if task.errorReport
          received_error task.errorReport, task.http_code, nil, {:rest_uri => task.uri, :rest_code => task.http_code}
        else
          rest_error "Status of task '"+task.uri.to_s+"' is no longer running (hasStatus is '"+task.status+
            "'), but it is neither completed nor has an errorReport"
        end 
      end
      @response
    end

    def self.rest_error message
      puts message
      raise OpenTox::RestCallError.new @request, @response, message
    end

    def self.received_error( body, code, content_type=nil, params=nil )

      # try to parse body TODO
      body.is_a?(OpenTox::ErrorReport) ? report = body : report = OpenTox::ErrorReport.from_rdf(body)
      rest_call_error "REST call returned error: '"+body.to_s+"'" unless report
      # parsing sucessfull
      # raise RestCallError with parsed report as error cause
      err = OpenTox::RestCallError.new(@request, @response, "REST call subsequent error")
      err.errorCause = report
      raise err
    end
=end
=begin
    def self.received_error( body, code, content_type=nil, params=nil )

      # try to parse body
      report = nil
      #report = OpenTox::ErrorReport.from_rdf(body)
      if body.is_a?(OpenTox::ErrorReport)
        report = body
      else
        case content_type
        when /yaml/
           report = YAML.load(body)
        when /rdf/
           report = OpenTox::ErrorReport.from_rdf(body)
        end
      end

      unless report
		    # parsing was not successfull
        # raise 'plain' RestCallError
        err = OpenTox::RestCallError.new("REST call returned error: '"+body.to_s+"'")
        err.rest_params = params
        raise err
      else
        # parsing sucessfull
        # raise RestCallError with parsed report as error cause
        err = OpenTox::RestCallError.new("REST call subsequent error")
        err.errorCause = report
        err.rest_params = params
        raise err
      end
    end
=end
  end
end
