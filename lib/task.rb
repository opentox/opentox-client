DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox

  # Class for handling asynchronous tasks
  class Task

    attr_accessor :pid, :observer_pid

    def self.create service_uri, params={}

      # TODO: run observer in same process?
      task = Task.new RestClientWrapper.post(service_uri,params).chomp
      pid = fork do
        begin
          result_uri = yield 
          task.completed result_uri
        rescue 
          RestClientWrapper.put(File.join(task.uri,'Error'),{:errorReport => $!.report.to_yaml}) if $!.respond_to? :report
          task.kill
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
    rescue # no need to raise an exeption if processes are not running
    end

    def description
      pull
      self.[](RDF::DC.description).uniq.first
    end

    def creator
      pull
      self.[](RDF::DC.creator).uniq.first
    end
    
    def cancel
      kill
      RestClientWrapper.put(File.join(@uri,'Cancelled'),{})
    end

    def completed(uri)
      not_found_error "Result URI \"#{uri}\" does not exist." unless URI.accessible? uri
      RestClientWrapper.put(File.join(@uri,'Completed'),{:resultURI => uri})
    end

    # waits for a task, unless time exceeds or state is no longer running
    # @param [optional,Numeric] dur seconds pausing before checking again for completion
    def wait(dur=0.3)
      due_to_time = Time.new + DEFAULT_TASK_MAX_DURATION
      while running?
        sleep dur
        time_out_error "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+@uri.to_s+"'" if (Time.new > due_to_time)
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

  # TODO: add queued?

  def error?
    code = RestClientWrapper.head(@uri).code
    code >= 400 and code != 503
  end

  def method_missing(method,*args)
    method = method.to_s
    response = self.[](RDF::OT[method])
    response = self.[](RDF::OT1[method]) if response.empty?  # API 1.1 compatibility
    internal_server_error "Unknown #{self.class} method #{method} for #{@uri}" if response.is_a? Array and response.empty?
    return response.to_s
  end

  #TODO: subtasks

end
