

module OpenTox

  # Shims for the Task class
  class Model

    def feature_type(subjectid=nil)
      unless @feature_type
        get unless metadata[OT.dependentVariables.to_s]
        raise "cannot determine feature type, dependent variable missing" unless metadata[OT.dependentVariables.to_s]
        @feature_type = OpenTox::Feature.find( metadata[OT.dependentVariables.to_s][0], subjectid ).feature_type
      end
      @feature_type
    end
    
    def predicted_variable(subjectid=nil)
      load_predicted_variables(subjectid) unless defined? @predicted_var 
      @predicted_var
    end
    
    def predicted_confidence(subjectid=nil)
      load_predicted_variables(subjectid) unless defined? @predicted_conf 
      @predicted_conf
    end
    
    private
    def load_predicted_variables(subjectid=nil)
      metadata[OT.predictedVariables.to_s].each do |f|
        feat = OpenTox::Feature.find( f, subjectid )
        if feat.title =~ /confidence/
          @predicted_conf = f
        else
          @predicted_var = f unless @predicted_var
        end 
      end
    end
    
  end
end