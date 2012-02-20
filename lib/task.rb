require File.join(File.dirname(__FILE__),'error')
DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox

  # Class for handling asynchronous tasks
  class Task

    attr_accessor :pid
    def self.create service_uri, params={}
      task = Task.new RestClient.post(service_uri,params).chomp
      pid = fork do
        begin
          result_uri = yield 
          if result_uri.uri?
            task.completed result_uri
          else
            raise "#{result_uri} is not a valid URI"
          end
        rescue 
          # TODO add service URI to Kernel.raise
          # serialize error and send to task service
          #task.error $!
          task.error $! 
          raise
        end
      end
      Process.detach(pid)
      task.pid = pid
      task
    end

    def kill
      begin
        Process.kill(9,pid)
      rescue 
      end
    end

    def description
      metadata[RDF::DC.description]
    end
    
    def cancel
      kill
      RestClient.put(File.join(@uri,'Cancelled'),{})
    end

    def completed(uri)
      RestClient.put(File.join(@uri,'Completed'),{:resultURI => uri})
    end

    def error error
      $logger.error self if $logger
      kill
      report = ErrorReport.create(error,"http://localhost")
      RestClient.put(File.join(@uri,'Error'),{:errorReport => report})
      #RestClient.put(File.join(@uri,'Error'),{:message => error, :backtrace => error.backtrace})
    end

    # waits for a task, unless time exceeds or state is no longer running
    # @param [optional,Numeric] dur seconds pausing before checking again for completion
    def wait_for_completion(dur=0.3)
      due_to_time = Time.new + DEFAULT_TASK_MAX_DURATION
      while running?
        sleep dur
        raise "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+@uri.to_s+"'" if (Time.new > due_to_time)
      end
    end

  end

  def method_missing(method,*args)
    method = method.to_s
    begin
      case method
      when /=/
        res = RestClient.put(File.join(@uri,method.sub(/=/,'')),{})
        super unless res.code == 200
      when /\?/
        return hasStatus == method.sub(/\?/,'').capitalize
      else
        response = metadata[RDF::OT[method]].to_s
        response = metadata[RDF::OT1[method]].to_s #if response.empty?  # API 1.1 compatibility
        if response.empty?
          $logger.error "No #{method} metadata for #{@uri} "
          raise "No #{method} metadata for #{@uri} "
        end
        return response
      end
    rescue
      $logger.error "Unknown #{self.class} method #{method}"
      #super
    end
  end

  # override to read all error codes
  def metadata reload=true
    if reload
      @metadata = {}
      # ignore error codes from Task services (may contain eg 500 which causes exceptions in RestClient and RDF::Reader
      RestClient.get(@uri) do |response, request, result, &block|
        $logger.warn "#{@uri} returned #{result}" unless response.code == 200 or response.code == 202
        RDF::Reader.for(:rdfxml).new(response) do |reader|
          reader.each_statement do |statement|
            @metadata[statement.predicate] = statement.object if statement.subject == @uri
          end
        end
      end
    end
    @metadata
  end

  #TODO: subtasks

end
