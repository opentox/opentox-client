module OpenTox

  # Wrapper for OpenTox Algorithms
  class Algorithm

    # Execute algorithm with parameters, please consult the OpenTox API and the webservice documentation for acceptable parameters
    # @param [optional,Hash] params Algorithm parameters
    # @param [optional,Boolean] wait  set to false if method should return a task uri instead of the algorithm result
    # @return [String] URI of new resource (dataset, model, ...)
    def run params=nil, wait=true
      uri = RestClientWrapper.post @uri, params, { :content_type => "text/uri-list", :subjectid => @subjectid}
      wait_for_task uri if wait
    end
  end

  module Descriptor

    class Smarts

      def self.fingerprint compounds, smarts, count=false
        matcher = Algorithm.new File.join($algorithm[:uri],"descriptor","smarts","fingerprint")
        smarts = [smarts] unless smarts.is_a? Array
        if compounds.is_a? OpenTox::Compound
          json = matcher.run :compound_uri => compounds.uri, :smarts => smarts, :count => count
        elsif compounds.is_a? OpenTox::Dataset
          # TODO: add task and return dataset instead of result
          json = matcher.run :dataset_uri => compounds.uri, :smarts => smarts, :count => count
        else
          bad_request_error "Cannot match smarts on #{compounds.class} objects."
        end
        
        JSON.parse json
      end

      def self.count compounds, smarts
        fingerprint compounds,smarts,true
      end
    end


  end
end
