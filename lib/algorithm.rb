module OpenTox

  # Wrapper for OpenTox Algorithms
  class Algorithm 

    # Execute algorithm with parameters, please consult the OpenTox API and the webservice documentation for acceptable parameters
    # @param [optional,Hash] params Algorithm parameters
    # @param [optional,OpenTox::Task] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [String] URI of new resource (dataset, model, ...)
    def run params=nil, wait=true
      uri = RestClientWrapper.post @uri, params, { :content_type => "text/uri-list", :subjectid => @subjectid}
      wait_for_task uri if wait
    end
  end
end
