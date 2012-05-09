DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox

  # Class for handling asynchronous tasks
  class Task

    attr_accessor :pid, :observer_pid

    def self.create service_uri, subjectid=nil, params={}

      uri = RDF::URI.new File.join(service_uri,SecureRandom.uuid)
      task = Task.new uri, subjectid
      task.rdf << RDF::Statement.new(uri, RDF.type, RDF::OT.Task)
      task.rdf << RDF::Statement.new(uri, RDF::DC.date, RDF::Literal.new(DateTime.now))
      task.rdf << RDF::Statement.new(uri, RDF::OT.hasStatus, RDF::Literal.new("Running"))
      params.each {|k,v| task.rdf << RDF::Statement.new(uri, k, v)}
      task.save
      pid = fork do
        begin
          result_uri = yield 
          task.completed result_uri
        rescue 
          if $!.respond_to? :to_ntriples
            RestClientWrapper.put(File.join(task.uri,'Error'),:errorReport => $!.to_ntriples,:content_type => 'text/plain') 
          else
            RestClientWrapper.put(File.join(task.uri,'Error')) 
          end
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
      #puts uri
      #not_found_error "Result URI \"#{uri}\" does not exist." unless URI.accessible? uri, @subjectid
      RestClientWrapper.put(File.join(@uri,'Completed'),{:resultURI => uri})
    end

    # waits for a task, unless time exceeds or state is no longer running
    # @param [optional,Numeric] dur seconds pausing before checking again for completion
    # TODO: add waiting task
    def wait
      start_time = Time.new
      due_to_time = start_time + DEFAULT_TASK_MAX_DURATION
      dur = 0.3
      while running? 
        sleep dur
        dur = [[(Time.new - start_time)/20.0,0.3].max,300.0].min
        time_out_error "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+@uri.to_s+"'" if (Time.new > due_to_time)
      end
    end

  end

  # get only header for status requests
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
    code = RestClientWrapper.head(@uri).code
    code >= 400 and code != 503
  end

  [:hasStatus, :resultURI].each do |method|
    define_method method do
      response = self.[](RDF::OT[method])
      response = self.[](RDF::OT1[method]) unless response  # API 1.1 compatibility
      response
    end
  end

  #TODO: subtasks (only for progress)

end
