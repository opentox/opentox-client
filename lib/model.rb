module OpenTox

  module Model

    def feature_type
      unless @feature_type
        bad_request_error "Cannot determine feature type, dependent variable missing in model #{@uri}" unless metadata[RDF::OT.dependentVariables]
        @feature_type = OpenTox::Feature.new( metadata[RDF::OT.dependentVariables][0]).feature_type
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
      metadata[RDF::OT.predictedVariables].each do |f|
        feat = OpenTox::Feature.new( f)
        if feat.title =~ /confidence/
          @predicted_confidence = f
        else
          @predicted_variable = f unless @predicted_variable
        end 
      end
    end

    class Generic
      include OpenTox
      include OpenTox::Algorithm
      include Model
    end

    class Lazar
      include OpenTox
      include OpenTox::Algorithm
      include Model
      def self.create params
        Lazar.new(File.join($algorithm[:uri], "lazar")).run params
      end

      def predict params
        run params
      end

    end

  end
end
