module OpenTox
  
  class WrapperResult < String
    attr_accessor :content_type, :code
  end
  
  class RestClientWrapper
    
    # performs a GET REST call
    # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
    # per default: waits for Task to finish and returns result URI of Task
    # @param [String] uri destination URI
    # @param [optional,Hash] headers contains params like accept-header
    # @param [optional,OpenTox::Task] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @param [wait,Boolean] wait set to false to NOT wait for task if result is task
    # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
    def self.get(uri, headers=nil, waiting_task=nil, wait=true )
      execute( "get", uri, headers, nil, waiting_task, wait)
    end
    
    # performs a POST REST call
    # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
    # per default: waits for Task to finish and returns result URI of Task
    # @param [String] uri destination URI
    # @param [optional,Hash] headers contains params like accept-header
    # @param [optional,String] payload data posted to the service
    # @param [optional,OpenTox::Task] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @param [wait,Boolean] wait set to false to NOT wait for task if result is task
    # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
    def self.post(uri, headers, payload=nil, waiting_task=nil, wait=true )
      execute( "post", uri, headers, payload, waiting_task, wait )
    end
    
    # performs a PUT REST call
    # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
    # @param [String] uri destination URI
    # @param [optional,Hash] headers contains params like accept-header
    # @param [optional,String] payload data put to the service
    # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
    def self.put(uri, headers, payload=nil )
      execute( "put", uri, headers, payload )
    end

    # performs a DELETE REST call
    # raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
    # @param [String] uri destination URI
    # @param [optional,Hash] headers contains params like accept-header
    # @return [OpenTox::WrapperResult] a String containing the result-body of the REST call
    def self.delete(uri, headers=nil )
      execute( "delete", uri, headers, nil)
    end

    # raises an Error message (rescued in overwrite.rb -> halt 502)
    # usage: if the return value of a call is invalid
    # @param [String] error_msg the error message 
    # @param [String] uri destination URI that is responsible for the error
    # @param [optional,Hash] headers sent to the URI
    # @param [optional,String] payload data sent to the URI  
    def self.raise_uri_error(error_msg, uri, headers=nil, payload=nil)
      raise_ot_error( nil, error_msg, nil, uri, headers, payload )         
    end
    
    private
    def self.execute( rest_call, uri, headers, payload=nil, waiting_task=nil, wait=true )
      
      raise OpenTox::BadRequestError.new "uri is null" unless uri
      raise OpenTox::BadRequestError.new "not a uri: "+uri.to_s unless uri.to_s.uri?
      raise OpenTox::BadRequestError.new "headers are no hash: "+headers.inspect unless headers==nil or headers.is_a?(Hash)
      raise OpenTox::BadRequestError.new "nil headers for post not allowed, use {}" if rest_call=="post" and headers==nil
      headers.each{ |k,v| headers.delete(k) if v==nil } if headers #remove keys with empty values, as this can cause problems
      
      begin
        #LOGGER.debug "RestCall: "+rest_call.to_s+" "+uri.to_s+" "+headers.inspect
        resource = RestClient::Resource.new(uri,{:timeout => 60}) 
        if payload
          result = resource.send(rest_call, payload, headers)
        elsif headers
          result = resource.send(rest_call, headers)
        else
          result = resource.send(rest_call)
        end
        
        # result is a string, with the additional fields content_type and code
        res = WrapperResult.new(result.body)
        res.content_type = result.headers[:content_type]
        raise "content-type not set" unless res.content_type
        res.code = result.code
        
        # TODO: Ambit returns task representation with 200 instead of result URI
        return res if res.code==200 || !wait
        
        while (res.code==201 || res.code==202)
          res = wait_for_task(res, uri, waiting_task)
        end
        raise "illegal status code: '"+res.code.to_s+"'" unless res.code==200
        return res
        
      rescue RestClient::RequestTimeout => ex
        raise_ot_error 408,ex.message,nil,ex.uri,headers,payload
      rescue RestClient::ExceptionWithResponse => ex
        raise_ot_error ex.http_code,ex.message,ex.http_body,uri,headers,payload
      rescue => ex
        raise_ot_error 500,ex.message,nil,uri,headers,payload
      end
    end
    
    def self.wait_for_task( res, base_uri, waiting_task=nil )
                          
      task = nil
      case res.content_type
      when /application\/rdf\+xml/
        task = OpenTox::Task.from_rdfxml(res)
      when /yaml/
        task = OpenTox::Task.from_yaml(res)
      when /text\//
        raise "uri list has more than one entry, should be a task" if res.content_type=~/text\/uri-list/ and res.split("\n").size > 1 #if uri list contains more then one uri, its not a task
        task = OpenTox::Task.find(res.to_s.chomp) if res.to_s.uri?
      else
        raise "unknown content-type for task: '"+res.content_type.to_s+"'" #+"' content: "+res[0..200].to_s
      end
      
      LOGGER.debug "result is a task '"+task.uri.to_s+"', wait for completion"
      task.wait_for_completion waiting_task
      raise task.description unless task.completed? # maybe task was cancelled / error
      
      res = WrapperResult.new task.result_uri
      res.code = task.http_code
      res.content_type = "text/uri-list"
      return res
    end
    
    def self.raise_ot_error( code, message, body, uri, headers, payload=nil )
      error = OpenTox::RestCallError.new("REST call returned error: '"+message.to_s+"'")
      error.rest_code = code
      error.rest_uri = uri
      error.rest_headers = headers
      error.rest_payload = payload
      parsed = OpenTox::ErrorReport.parse(body) if body
      if parsed
        error.errorCause = parsed
      else
        error.rest_body = body
      end
      raise error
    end
  end
end
