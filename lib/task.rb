DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox
  # TODO: fix error reports
  # TODO: fix field names and overwrite accessors

  # Class for handling asynchronous tasks
  class Task 

    field :creator, type: String
    field :percentageCompleted, type: Float
    field :error_code, type: Integer # workaround name, cannot overwrite accessors in current mongoid version
    field :finished, type: Time # workaround name, cannot overwrite accessors in current mongoid version
    # TODO
    field :result_object, type: String
    field :report, type: String
    field :pid, type: Integer
    field :observer_pid, type: Integer

    def self.run(description, creator=nil)

      task = Task.new
      task[:description] = description.to_s
      task[:creator] = creator.to_s
      task[:percentageCompleted] = 0
      task[:error_code] = 202 
      task.save

      pid = fork do
        begin
          task.completed yield
        rescue => e
          # wrap non-opentox-errors first
          e = OpenTox::Error.new(500,e.message,nil,e.backtrace) unless e.is_a?(OpenTox::Error)
          $logger.error "error in task #{task.id} created by #{creator}" # creator is not logged because error is logged when thrown
          task.update(:report => e.metadata, :error_code => e.http_code, :finished => Time.now)
          task.kill
        end
      end
      Process.detach(pid)
      task[:pid] = pid

      # watch if task has been cancelled 
      observer_pid = fork do
        task.wait
        begin
          Process.kill(9,task[:pid]) if task.cancelled?
        rescue
          $logger.warn "Could not kill process of task #{task.id}, pid: #{task[:pid]}"
        end
      end
      Process.detach(observer_pid)
      task[:observer_pid] = observer_pid
      task

    end

    def kill
      Process.kill(9,task[:pid])
      Process.kill(9,task[:observer_pid])
    rescue # no need to raise an exception if processes are not running
    end

    def cancel
      kill
      update_attributes(:error_code => 503, :finished => Time.now)
    end

    def completed(result)
      update_attributes(:error_code => 200, :finished => Time.now, :percentageCompleted => 100, :result_object => result)
    end

    # waits for a task, unless time exceeds or state is no longer running
    def wait
      start_time = Time.new
      due_to_time = start_time + DEFAULT_TASK_MAX_DURATION
      dur = 0.2
      while running? 
        sleep dur
        dur = [[(Time.new - start_time)/20.0,0.3].max,300.0].min
        request_timeout_error "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+id.to_s+"'" if (Time.new > due_to_time)
      end
    end

  end

  def error_report
    OpenTox::Task.find(id).report
  end

  def code
    OpenTox::Task.find(id).error_code
  end

  def result
    OpenTox::Task.find(id).result_object
  end

  def finished_at
    OpenTox::Task.find(id).finished
  end

  def running?
    code == 202 
  end

  def cancelled?
    code == 503
  end

  def completed?
    code == 200
  end

  def error?
    code >= 400 and code != 503
  end

  # Check status of a task
  # @return [String] Status
  def status
    case code
    when 202
      "Running"
    when 200
      "Completed"
    when 503
      "Cancelled"
    else
      "Error"
    end
  end

end
