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
    [:head,:get,:post,:put,:dealete].each do |method|

      define_singleton_method method do |uri,payload={},headers={},waiting_task=nil, wait=true|
      
        # create request
        args={}
        args[:method] = method
        args[:url] = uri
        args[:timeout] = 600
        args[:payload] = payload
        headers.each{ |k,v| headers.delete(k) if v==nil } if headers #remove keys with empty values, as this can cause problems
        args[:headers] = headers 
        @request = RestClient::Request.new(args)

        # check input 
        raise OpenTox::BadRequestError.new "Invalid URI: '#{uri}'" unless URI.valid? uri
        raise OpenTox::BadRequestError.new "Unreachable URI: '#{uri}'" unless URI.accessible? uri
        raise OpenTox::BadRequestError.new "Headers are not a hash: #{headers.inspect}" unless headers==nil or headers.is_a?(Hash)
        # make sure that no header parameters are set in the payload
        [:accept,:content_type,:subjectid].each do |header|
          raise OpenTox::BadRequestError.new "#{header} should be submitted in the headers" if payload and payload.is_a?(Hash) and payload[header] 
        end
        raise OpenTox::BadRequestError.new "waiting_task is not 'nil', OpenTox::SubTask or OpenTox::Task: #{waiting_task.class}" unless waiting_task.nil? or waiting_task.is_a?(OpenTox::Task) or waiting_task.is_a?(OpenTox::SubTask)

        
        begin
          @response = @request.execute do |response, request, result|
            # ignore error codes from Task services (may contain eg 500 which causes exceptions in RestClient and RDF::Reader
            rest_error "Response code is #{response.code}" unless response.code < 400 or URI.task? uri
            return response
          end
          
          return @response if @response.code==200 or !wait

          # wait for task
          while @response.code==201 or @response.code==202
            @response = wait_for_task(@response, uri, waiting_task)
          end
          return @response
          
        rescue
          rest_error $!.message
        end
=begin
        rescue RestClient::RequestTimeout 
          raise OpenTox::Error @request, @response, $!.message
          #received_error ex.message, 408, nil, {:rest_uri => uri, :headers => headers, :payload => payload}
        rescue Errno::ETIMEDOUT 
          raise OpenTox::Error @request, @response, $!.message
          #received_error ex.message, 408, nil, {:rest_uri => uri, :headers => headers, :payload => payload}
        rescue Errno::ECONNREFUSED
          raise OpenTox::Error $!.message
          #received_error ex.message, 500, nil, {:rest_uri => uri, :headers => headers, :payload => payload}
        rescue RestClient::ExceptionWithResponse
          # error comming from a different webservice, 
          received_error ex.http_body, ex.http_code, ex.response.net_http_res.content_type, {:rest_uri => uri, :headers => headers, :payload => payload}
        #rescue OpenTox::RestCallError => ex
          # already a rest-error, probably comes from wait_for_task, just pass through
          #raise ex       
        #rescue => ex
          # some internal error occuring in rest-client-wrapper, just pass through
          #raise ex
        end
=end
      end
    end
    
    def wait_for_task( response, base_uri, waiting_task=nil )
      #TODO remove TUM hack
      # @response.headers[:content_type] = "text/uri-list" if base_uri =~/tu-muenchen/ and @response.headers[:content_type] == "application/x-www-form-urlencoded;charset=UTF-8"

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
      
      #LOGGER.debug "result is a task '"+task.uri.to_s+"', wait for completion"
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
      raise OpenTox::RestCallError.new @request, @response, message
    end

=begin
    def self.bad_request_error message
      raise OpenTox::Error.new message
    end

    def self.not_found_error message
      raise OpenTox::NotFoundError.new message
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
