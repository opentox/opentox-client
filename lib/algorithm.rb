module OpenTox

  # Wrapper for OpenTox Algorithms
  module Algorithm
    include OpenTox

    # Execute algorithm with parameters, please consult the OpenTox API and the webservice documentation for acceptable parameters
    # @param [optional,Hash] params Algorithm parameters
    # @param [optional,Boolean] wait  set to false if method should return a task uri instead of the algorithm result
    # @return [String] URI of new resource (dataset, model, ...)
    def run params=nil, wait=true
      uri = RestClientWrapper.post @uri, params, { :content_type => "text/uri-list", :subjectid => @subjectid}
      wait_for_task uri if wait
    end

    class Generic
      include OpenTox
      include Algorithm
    end

    class Descriptor 
      include OpenTox
      include Algorithm

      [:smarts_match,:smarts_count,:openbabel,:cdk,:joelib,:physchem,:lookup].each do |descriptor|
        Descriptor.define_singleton_method(descriptor) do |compounds,descriptors|
          descriptors = [descriptors] unless descriptors.is_a? Array
          case compounds.class.to_s
          when "Array"
            klasses = compounds.collect{|c| c.class}.uniq
            bad_request_error "First argument contains objects with a different class than OpenTox::Compound or OpenTox::Dataset #{klasses.inspect}" unless klasses.size == 1 and klasses.first == Compound
            JSON.parse(Descriptor.new(File.join(self.service_uri, "descriptor", descriptor.to_s), SUBJECTID).run(:compound_uri => compounds.collect{|c| c.uri}, :descriptors => descriptors))
          when "OpenTox::Compound"
            JSON.parse(Descriptor.new(File.join(self.service_uri, "descriptor", descriptor.to_s), SUBJECTID).run(:compound_uri => compounds.uri, :descriptors => descriptors))
          when "OpenTox::Dataset"
            task_uri = Descriptor.new(File.join(self.service_uri, "descriptor", descriptor.to_s), SUBJECTID).run(:dataset_uri => compounds.uri, :descriptors => descriptors)
            puts task_uri
            #task_uri
            Dataset.new(Task.new(task_uri).wait_for_task)
          else
            bad_request_error "First argument contains objects with a different class than OpenTox::Compound or OpenTox::Dataset" 
          end

        end
      end

    end

    class Fminer 
      include OpenTox
      include Algorithm
      def self.bbrc params
        Fminer.new(File.join(service_uri, "fminer", "bbrc")).run params
      end
      def self.last params
        Fminer.new(File.join(service_uri, "fminer", "last")).run params
      end
    end

  end
end
