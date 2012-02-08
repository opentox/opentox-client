DEFAULT_TASK_MAX_DURATION = 36000
module OpenTox

  # Class for handling asynchronous tasks
  class Task


    def self.create service_uri
      Task.new RestClient.post(service_uri,{}).chomp
      #eval("#{self}.new(\"#{uri}\", #{subjectid})")
    end

    def http_code
      get(@uri).code
    end

    def status
      metadata[RDF::OT.hasStatus].to_s
    end

    def result_uri
      metadata[RDF::OT.resultURI]
    end

    def description
      metadata[RDF::DC.description]
    end
    
    def errorReport
      metadata[RDF::OT.errorReport]
    end
    
    def cancel
      RestClient.put(File.join(@uri,'Cancelled'),{:cannot_be => "empty"})
    end

    def completed(uri)
      RestClient.put(File.join(@uri,'Completed'),{:resultURI => uri})
    end

    def error(error_report)
      raise "no error report" unless error_report.is_a?(OpenTox::ErrorReport)
      RestClient.put(File.join(@uri,'Error'),{:errorReport => error_report.to_yaml})
    end
    
    def pid=(pid)
      RestClient.put(File.join(@uri,'pid'), {:pid => pid})
    end

    def running?
      metadata[RDF::OT.hasStatus] == 'Running'
    end

    def completed?
      metadata[RDF::OT.hasStatus] == 'Completed'
    end

    def error?
      metadata[RDF::OT.hasStatus] == 'Error'
    end

    # waits for a task, unless time exceeds or state is no longer running
    # @param [optional,Numeric] dur seconds pausing before cheking again for completion
    def wait_for_completion(dur=0.3)
      due_to_time = Time.new + DEFAULT_TASK_MAX_DURATION
      while self.running?
        raise "max wait time exceeded ("+DEFAULT_TASK_MAX_DURATION.to_s+"sec), task: '"+@uri.to_s+"'" if (Time.new > due_to_time)
      end
    end
  end

end
