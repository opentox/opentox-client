module OpenTox
  
  class RestClientWrapper
    
    attr_accessor :request, :response

    # REST methods 
    # Raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
    # Waits for Task to finish and returns result URI of Task per default
    # @param [String] destination URI
    # @param [optional,Hash|String] Payload data posted to the service
    # @param [optional,Hash] Headers with params like :accept, :content_type, :subjectid
    # @return [RestClient::Response] REST call response 
    [:head,:get,:post,:put,:delete].each do |method|

      define_singleton_method method do |uri,payload={},headers={}|

        # check input 
        @subjectid = headers[:subjectid] ? headers[:subjectid] : nil
        bad_request_error "Invalid URI: '#{uri}'" unless URI.valid? uri
        #not_found_error "URI '#{uri}' not found." unless URI.accessible?(uri, @subjectid) unless URI.ssl?(uri)
        bad_request_error "Headers are not a hash: #{headers.inspect}" unless headers==nil or headers.is_a?(Hash)
        # make sure that no header parameters are set in the payload
        [:accept,:content_type,:subjectid].each do |header|
          if defined? $aa || URI(uri).host == URI($aa[:uri]).host
          else
            bad_request_error "#{header} should be submitted in the headers" if payload and payload.is_a?(Hash) and payload[header]
          end
        end
      
        # create request
        args={}
        args[:method] = method
        args[:url] = uri
        args[:timeout] = 600
        args[:payload] = payload
        headers.each{ |k,v| headers.delete(k) if v==nil } if headers #remove keys with empty values, as this can cause problems
        args[:headers] = headers 

        @request = RestClient::Request.new(args)
        # ignore error codes from Task services (may return error codes >= 400 according to API, which causes exceptions in RestClient and RDF::Reader)
        @response = @request.execute do |response, request, result|
          if [301, 302, 307].include? response.code and request.method == :get
            response.follow_redirection(request, result)
          elsif response.code >= 400 and !URI.task?(uri)
            message = response.to_s
            message += "\nREST paramenters:\n#{request.args.inspect}" 
            case response.code
            when 400
              bad_request_error message, uri
            when 401
              not_authorized_error message, uri
            when 404
              not_found_error message, uri
            when 433
              locked_error message, uri
            when 500
              internal_server_error message, uri
            when 501
              not_implemented_error message, uri
            when 503
              service_unavailable_error message, uri
            when 504
              time_out_error message, uri
            else
              rest_call_error message, uri
            end
          else
            response
          end
        end
      end
    end

  end
end
