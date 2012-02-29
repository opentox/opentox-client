require File.join(File.dirname(__FILE__),'error')
DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox

  # Class for handling asynchronous tasks
  class Task

    attr_accessor :pid, :observer_pid

    def self.create service_uri, params={}

      # TODO set request uri
      task = Task.new RestClientWrapper.post(service_uri,params).chomp
      pid = fork do
        begin
          result_uri = yield 
          if URI.accessible?(result_uri)
            task.completed result_uri
          else
            task.error OpenTox::RestError.new :http_code => 404, :cause => "#{result_uri} is not a valid URI", :actor => params[:creator]
          end
        rescue 
          task.error $! 
        end
      end
      Process.detach(pid)
      task.pid = pid

      # watch if task has been cancelled 
      observer_pid = fork do
        task.wait
        begin
          Process.kill(9,task.pid) if task.cancelled?
        rescue
          $logger.warn "Could not kill process of task #{task.uri}, pid: #{task.pid}"
        end
      end
      Process.detach(observer_pid)
      task.observer_pid = observer_pid
      task

    end

    def kill
      Process.kill(9,@pid)
      Process.kill(9,@observer_pid)
      rescue # no need to raise an aexeption if processes are not running
    end

    def description
      metadata[RDF::DC.description]
    end

    def creator
      metadata[RDF::DC.creator]
    end
    
    def cancel
      kill
      RestClientWrapper.put(File.join(@uri,'Cancelled'),{})
    end

    def completed(uri)
      #TODO: subjectid?
      #TODO: error code
      error OpenTox::RestError.new :http_code => 404, :cause => "\"#{uri}\" does not exist.", :actor => creator unless URI.accessible? uri
      RestClientWrapper.put(File.join(@uri,'Completed'),{:resultURI => uri})
    end

    def error error
      error = OpenTox::TaskError.new error, self.creator
      RestClientWrapper.put(File.join(@uri,'Error'),{:errorReport => error.report})
      kill
      raise error
    end

    # waits for a task, unless time exceeds or state is no longer running
    # @param [optional,Numeric] dur seconds pausing before checking again for completion
    def wait(dur=0.3)
      due_to_time = Time.new + DEFAULT_TASK_MAX_DURATION
      while running?
        sleep dur
        raise "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+@uri.to_s+"'" if (Time.new > due_to_time)
      end
    end

  end

  # get only header for ststus requests
  def running?
    RestClientWrapper.head(@uri).code == 202 
  end

  def cancelled?
    RestClientWrapper.head(@uri).code == 503
  end

  def completed?
    RestClientWrapper.head(@uri).code == 200
  end

  def error?
    RestClientWrapper.head(@uri).code == 500
  end

  def method_missing(method,*args)
    method = method.to_s
    begin
      case method
      when /=/
        res = RestClientWrapper.put(File.join(@uri,method.sub(/=/,'')),{})
        super unless res.code == 200
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

  #TODO: subtasks

end
