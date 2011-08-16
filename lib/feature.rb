module OpenTox
  class Feature
    include OpenTox

    attr_accessor :subjectid

    # Find a feature
    # @param [String] uri Feature URI
    # @return [OpenTox::Feature] Feature object
    def self.find(uri, subjectid=nil)
      return nil unless uri   
      feature = Feature.new uri, subjectid
      if (CONFIG[:yaml_hosts].include?(URI.parse(uri).host))
        feature.add_metadata YAML.load(RestClientWrapper.get(uri,{:accept => "application/x-yaml", :subjectid => @subjectid}))
      else
        feature.add_metadata  Parser::Owl::Dataset.new(uri).load_metadata
      end
      feature.subjectid = subjectid
      feature
    end

    # provides feature type, possible types are "regression" or "classification"
    # @return [String] feature type, unknown if OT.isA property is unknown/ not set
    def feature_type
      if metadata[RDF.type].flatten.include?(OT.NominalFeature)
        "classification"
      elsif metadata[RDF.type].flatten.include?(OT.NumericFeature)
        "regression"
      elsif metadata[OWL.sameAs]
        metadata[OWL.sameAs].each do |f|
          begin
            type = Feature.find(f, subjectid).feature_type
            return type unless type=="unknown"
          rescue => ex
            LOGGER.warn "could not load same-as-feature '"+f.to_s+"' for feature '"+uri.to_s+"' : "+ex.message.to_s
          end
        end
        "unknown"
      else
        "unknown"
      end
    end    
  end
end
