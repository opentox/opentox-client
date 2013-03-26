module OpenTox

  class Model

    # Run a model with parameters
    # @param [Hash] params Parameters for OpenTox model
    # @param [optional,OpenTox::Task] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [text/uri-list] Task or resource URI
    def run params=nil, wait=true
      uri = RestClientWrapper.post @uri, params, { :content_type => "text/uri-list", :subjectid => @subjectid}
      wait_for_task uri if wait
    end

    def feature_type # CH: subjectid is a object variable, no need to pass it as a parameter
      unless @feature_type
        get unless metadata[OT.dependentVariables.to_s]
        bad_request_error "Cannot determine feature type, dependent variable missing in model #{@uri}" unless metadata[OT.dependentVariables.to_s]
        @feature_type = OpenTox::Feature.new( metadata[OT.dependentVariables.to_s][0], @subjectid ).feature_type
      end
      @feature_type
    end
    
    def predicted_variable
      load_predicted_variables unless defined? @predicted_variable
      @predicted_variable
    end
    
    def predicted_confidence
      load_predicted_variables unless defined? @predicted_confidence
      @predicted_confidence
    end
    
    private
    def load_predicted_variables
      metadata[OT.predictedVariables.to_s].each do |f|
        feat = OpenTox::Feature.find( f, @subjectid )
        if feat.title =~ /confidence/
          @predicted_confidence = f
        else
          @predicted_variable = f unless @predicted_variable
        end 
      end
    end

  end
end
