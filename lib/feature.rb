module OpenTox

  class Feature

    # Find out feature type
    # Classification takes precedence
    # @return [String] Feature type
    def feature_type
      if self[RDF.type].include?(RDF::OT.NominalFeature)
        "classification"
      elsif self[RDF.type].include?(RDF::OT.NumericFeature)
        "regression"
      else
        "unknown"
      end
    end

    # Get accept values
    # 
    # @return[Array] Accept values
    def accept_values
      self[RDF::OT.acceptValue] ? self[RDF::OT.acceptValue].sort : nil
    end

    # Create value map
    # @param [OpenTox::Feature] Feature
    # @return [Hash] A hash with keys 1...feature.training_classes.size and values training classes
    def value_map
      unless defined? @value_map
        accept_values ? @value_map = accept_values.each_index.inject({}) { |h,idx| h[idx+1]=accept_values[idx]; h } : @value_map = nil
      end
      @value_map
    end

  end

end
