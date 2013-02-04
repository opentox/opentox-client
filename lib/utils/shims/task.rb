=begin
* Name: task.rb
* Description: Task shims
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end


module OpenTox

  # Shims for the Task class
  class Task

    def self.run(description, creator, subjectid=nil)
       create($task[:uri],subjectid,{ RDF::DC.description => description, RDF::DC.creator => creator},&Proc.new) 
    end

    # Check status of a task
    # @return [String] Status
    def status
      self[RDF::OT.hasStatus]
    end
    
    def code
      RestClientWrapper.head(@uri).code
    end

  end

end


module OpenTox

  class SubTask
    
    def initialize(task, min, max)
      #TODO add subtask code
    end

    def self.create(task, min, max)
      if task
        SubTask.new(task, min, max)
      else
        nil
      end
    end
    
    def waiting_for(task_uri)
      #TODO add subtask code
    end
    
    def progress(pct)
      #TODO add subtask code
    end
    
    def running?()
      #TODO add subtask code
    end
  end
  
end