require "yaml"

module OldOpenTox
  attr_accessor :metadata, :uri

  def initialize(uri=nil)
    @metadata = {}
    self.uri = uri if uri
  end

  # loads metadata via yaml
  def load_metadata
    yaml = OpenTox::RestClientWrapper.get(uri,nil,{:accept => "application/x-yaml"})
    @metadata = YAML.load(yaml)
  end

  def delete 
    OpenTox::RestClientWrapper.delete @uri.to_s
  end
end

module OpenTox

  class Validation
    include OldOpenTox

    # find validation, raises error if not found
    # @param [String] uri
    # @return [OpenTox::Validation]
    def self.find( uri )
      val = Validation.new(uri)
      val.load_metadata
      val
    end

    # returns a filtered list of validation uris
    # @param params [Hash,optional] validation-params to filter the uris (could be model, training_dataset, ..)
    # @return [Array]
    def self.list( params={} )
      filter_string = ""
      params.each do |k,v|
        filter_string += (filter_string.length==0 ? "?" : "&")
        v = v.to_s.gsub(/;/, "%3b") if v.to_s =~ /;/
        filter_string += k.to_s+"="+v.to_s
      end
      (OpenTox::RestClientWrapper.get($validation[:uri]+filter_string).split("\n"))
    end

    # creates a training test split validation, waits until it finishes, may take some time
    # @param [Hash] params (required:algorithm_uri,dataset_uri,prediction_feature, optional:algorithm_params,split_ratio(0.67),random_seed(1))
    # @param [OpenTox::Task,optional] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [OpenTox::Validation]
    def self.create_training_test_split( params, waiting_task=nil )
      uri = OpenTox::RestClientWrapper.post( File.join($validation[:uri],"training_test_split"),
        params,{:content_type => "text/uri-list"},waiting_task )
      Validation.new(wait_for_task(uri))
    end

    # creates a training test validation, waits until it finishes, may take some time
    # @param [Hash] params (required:algorithm_uri,training_dataset_uri,prediction_feature,test_dataset_uri,optional:algorithm_params)
    # @param [OpenTox::Task,optional] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [OpenTox::Validation]
    def self.create_training_test_validation( params, waiting_task=nil )
      uri = OpenTox::RestClientWrapper.post( File.join($validation[:uri],"training_test_validation"),
        params,{:content_type => "text/uri-list"},waiting_task )
      Validation.new(wait_for_task(uri))
    end

    # creates a bootstrapping validation, waits until it finishes, may take some time
    # @param [Hash] params (required:algorithm_uri,dataset_uri,prediction_feature, optional:algorithm_params,random_seed(1))
    # @param [OpenTox::Task,optional] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [OpenTox::Validation]
    def self.create_bootstrapping_validation( params, waiting_task=nil )
      uri = OpenTox::RestClientWrapper.post( File.join($validation[:uri],"bootstrapping"),
        params,{:content_type => "text/uri-list"},waiting_task )
      Validation.new(wait_for_task(uri))
    end

    # looks for report for this validation, creates a report if no report is found
    # @param [OpenTox::Task,optional] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [String] report uri
    def find_or_create_report( waiting_task=nil )
      @report = ValidationReport.find_for_validation(@uri) unless @report
      @report = ValidationReport.create(@uri, waiting_task) unless @report
      @report.uri
    end

    # creates a validation object from crossvaldiation statistics, raise error if not found
    # (as crossvaldiation statistics are returned as an average valdidation over all folds)
    # @param crossvalidation_uri [String] crossvalidation uri
    # @return [OpenTox::Validation]
    def self.from_cv_statistics( crossvalidation_uri )
      find( File.join(crossvalidation_uri, 'statistics') )
    end

    # returns confusion matrix as array, predicted values are in rows
    # @example
    #  [[nil,"active","moderate","inactive"],["active",1,3,99],["moderate",4,2,8],["inactive",3,8,6]]
    # -> 99 inactive compounds have been predicted as active
    def confusion_matrix
      raise "no classification statistics, probably a regression valdiation" unless @metadata[RDF::OT.classificationStatistics]
      matrix =  @metadata[RDF::OT.classificationStatistics][RDF::OT.confusionMatrix][RDF::OT.confusionMatrixCell]
      values = matrix.collect{|cell| cell[RDF::OT.confusionMatrixPredicted]}.uniq
      table = [[nil]+values]
      values.each do |c|
        table << [c]
        values.each do |r|
          matrix.each do |cell|
            if cell[RDF::OT.confusionMatrixPredicted]==c and cell[RDF::OT.confusionMatrixActual]==r
              table[-1] << cell[RDF::OT.confusionMatrixValue].to_f
              break
            end
          end
        end
      end
      table
    end

    # filters the validation-predictions and returns validation-metadata with filtered statistics
    # @param min_confidence [Float] predictions with confidence < min_confidence are filtered out
    # @param min_num_predictions [Integer] optional, additional param to min_confidence, the top min_num_predictions are selected, even if confidence to low
    # @param max_num_predictions [Integer] returns the top max_num_predictions (with the highest confidence), not compatible to min_confidence
    # return [Hash] metadata
    def filter_metadata( min_confidence, min_num_predictions=nil, max_num_predictions=nil )
      conf = min_confidence ? "min_confidence=#{min_confidence}" : nil
      min = min_num_predictions ? "min_num_predictions=#{min_num_predictions}" : nil
      max = max_num_predictions ? "max_num_predictions=#{max_num_predictions}" : nil
      YAML.load(OpenTox::RestClientWrapper.get("#{@uri}?#{[conf,min,max].compact.join("&")}",nil,{:accept => "application/x-yaml"}))
    end

    # returns probability-distribution for a given prediction
    # it takes all predictions into account that have a confidence value that is >= confidence and that have the same predicted value
    # (minimum 12 predictions with the hightest confidence are selected (even if the confidence is lower than the given param)
    #
    # @param confidence [Float] confidence value (between 0 and 1)
    # @param prediction [String] predicted value
    # @return [Hash] see example
    # @example
    #  Example 1:
    #   validation.probabilities(0.3,"active")
    #   -> { :min_confidence=>0.32, :num_predictions=>20, :probs=>{"active"=>0.7, "moderate"=>0.25 "inactive"=>0.05 } }
    #  there have been 20 "active" predictions with confidence >= 0.3, 70 percent of them beeing correct
    #
    #  Example 2:
    #   validation.probabilities(0.8,"active")
    #   -> { :min_confidence=>0.45, :num_predictions=>12, :probs=>{"active"=>0.9, "moderate"=>0.1 "inactive"=>0 } }
    #  the given confidence value was to high (i.e. <12 predictions with confidence value >= 0.8)
    #  the top 12 "active" predictions have a min_confidence of 0.45, 90 percent of them beeing correct
    #
    def probabilities( confidence, prediction )
      YAML.load(OpenTox::RestClientWrapper.get(@uri+"/probabilities?prediction="+prediction.to_s+"&confidence="+confidence.to_s,nil,
        {:accept => "application/x-yaml"}))
    end
  end

  class Crossvalidation
    include OldOpenTox

    attr_reader :report

    # find crossvalidation, raises error if not found
    # @param [String] uri
    # @return [OpenTox::Crossvalidation]
    def self.find( uri )
      cv = Crossvalidation.new(uri)
      cv.load_metadata
      cv
    end

    # returns a filtered list of crossvalidation uris
    # @param params [Hash,optional] crossvalidation-params to filter the uris (could be algorithm, dataset, ..)
    # @return [Array]
    def self.list( params={} )
      filter_string = ""
      params.each do |k,v|
        filter_string += (filter_string.length==0 ? "?" : "&")
        v = v.to_s.gsub(/;/, "%3b") if v.to_s =~ /;/
        filter_string += k.to_s+"="+v.to_s
      end
      (OpenTox::RestClientWrapper.get(File.join($validation[:uri],"crossvalidation")+filter_string).split("\n"))
    end
		
    # creates a crossvalidations, waits until it finishes, may take some time
    # @param [Hash] params (required:algorithm_uri,dataset_uri,prediction_feature, optional:algorithm_params,num_folds(10),random_seed(1),stratified(false))
    # @param [OpenTox::Task,optional] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [OpenTox::Crossvalidation]
    def self.create( params, waiting_task=nil )
      uri = OpenTox::RestClientWrapper.post( File.join($validation[:uri],"crossvalidation"),
        params,{:content_type => "text/uri-list"},waiting_task )
      uri = wait_for_task(uri)
      Crossvalidation.new(uri)
    end

    # looks for report for this crossvalidation, creates a report if no report is found
    # @param [OpenTox::Task,optional] waiting_task (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [String] report uri
    def find_or_create_report( waiting_task=nil )
      @report = CrossvalidationReport.find_for_crossvalidation(@uri) unless @report
      @report = CrossvalidationReport.create(@uri, waiting_task) unless @report
      @report.uri
    end

    # loads metadata via yaml from crossvalidation object
    # fields (like for example the validations) can be acces via validation.metadata[RDF::OT.validation]
    def load_metadata
      @metadata = YAML.load(OpenTox::RestClientWrapper.get(uri,nil,{:accept => "application/x-yaml"}))
    end

    # returns a Validation object containing the statistics of the crossavlidation
    def statistics
      Validation.from_cv_statistics( @uri )
    end

    # documentation see OpenTox::Validation.probabilities
    def probabilities( confidence, prediction )
      YAML.load(OpenTox::RestClientWrapper.get(@uri+"/statistics/probabilities?prediction="+prediction.to_s+"&confidence="+confidence.to_s,nil,
        {:accept => "application/x-yaml"}))
    end

  end

  class ValidationReport
    include OldOpenTox

    # finds ValidationReport via uri, raises error if not found
    # @param [String] uri
    # @return [OpenTox::ValidationReport]
    def self.find( uri )
      OpenTox::RestClientWrapper.get(uri)
      rep = ValidationReport.new(uri)
      rep.load_metadata
      rep
    end

    # finds ValidationReport for a particular validation
    # @param validation_uri [String] crossvalidation uri
    # @return [OpenTox::ValidationReport] nil if no report found
    def self.find_for_validation( validation_uri )
      uris = RestClientWrapper.get(File.join($validation[:uri],
        "/report/validation?validation="+validation_uri)).chomp.split("\n")
      uris.size==0 ? nil : ValidationReport.new(uris[-1])
    end

    # creates a validation report via validation
    # @param validation_uri [String] validation uri
    # @param params [Hash] params addiditonal possible
    #               (min_confidence, params={}, min_num_predictions, max_num_predictions)
    # @param waiting_task [OpenTox::Task,optional] (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [OpenTox::ValidationReport]
    def self.create( validation_uri, params={}, waiting_task=nil )
      params = {} if params==nil
      bad_request_error "params is no hash" unless params.is_a?(Hash)
      params[:validation_uris] = validation_uri
      uri = RestClientWrapper.post(File.join($validation[:uri],"/report/validation"),
        params, {}, waiting_task )
      uri = wait_for_task(uri)
      ValidationReport.new(uri)
    end

  end

  class CrossvalidationReport
    include OldOpenTox

    # finds CrossvalidationReport via uri, raises error if not found
    # @param [String] uri
    # @return [OpenTox::CrossvalidationReport]
    def self.find( uri )
      OpenTox::RestClientWrapper.get(uri)
      rep = CrossvalidationReport.new(uri)
      rep.load_metadata
      rep
    end

    # finds CrossvalidationReport for a particular crossvalidation
    # @param crossvalidation_uri [String] crossvalidation uri
    # @return [OpenTox::CrossvalidationReport] nil if no report found
    def self.find_for_crossvalidation( crossvalidation_uri )
      uris = RestClientWrapper.get(File.join($validation[:uri],
        "/report/crossvalidation?crossvalidation="+crossvalidation_uri)).chomp.split("\n")
      uris.size==0 ? nil : CrossvalidationReport.new(uris[-1])
    end

    # creates a crossvalidation report via crossvalidation
    # @param crossvalidation_uri [String] crossvalidation uri
    # @param waiting_task [OpenTox::Task,optional] (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [OpenTox::CrossvalidationReport]
    def self.create( crossvalidation_uri, waiting_task=nil )
      uri = RestClientWrapper.post(File.join($validation[:uri],"/report/crossvalidation"),
        { :validation_uris => crossvalidation_uri }, {}, waiting_task )
      uri = wait_for_task(uri)
      CrossvalidationReport.new(uri)
    end
  end


  class AlgorithmComparisonReport
    include OldOpenTox

    # finds AlgorithmComparisonReport via uri, raises error if not found
    # @param [String] uri
    # @return [OpenTox::CrossvalidationReport]
    def self.find( uri )
      OpenTox::RestClientWrapper.get(uri)
      rep = AlgorithmComparisonReport.new(uri)
      rep.load_metadata
      rep
    end

    # finds AlgorithmComparisonReport for a particular crossvalidation
    # @param crossvalidation_uri [String] crossvalidation uri
    # @return [OpenTox::AlgorithmComparisonReport] nil if no report found
    def self.find_for_crossvalidation( crossvalidation_uri )
      uris = RestClientWrapper.get(File.join($validation[:uri],
        "/report/algorithm_comparison?crossvalidation="+crossvalidation_uri)).chomp.split("\n")
      uris.size==0 ? nil : AlgorithmComparisonReport.new(uris[-1])
    end

    # creates a algorithm comparison report via crossvalidation uris
    # @param crossvalidation_uri_hash [Hash] crossvalidation uri_hash, see example
    # @param params [Hash] params addiditonal possible
    #               (ttest_significance, ttest_attributes, min_confidence, min_num_predictions, max_num_predictions)
    # @param waiting_task [OpenTox::Task,optional] (can be a OpenTox::Subtask as well), progress is updated accordingly
    # @return [OpenTox::AlgorithmComparisonReport]
    # example for hash:
    # { :lazar-bbrc => [ http://host/validation/crossvalidation/x1, http://host/validation/crossvalidation/x2 ],
    #   :lazar-last => [ http://host/validation/crossvalidation/xy, http://host/validation/crossvalidation/xy ] }
    def self.create( crossvalidation_uri_hash, params={}, waiting_task=nil )
      identifier = []
      validation_uris = []
      crossvalidation_uri_hash.each do |id, uris|
        uris.each do |uri|
          identifier << id
          validation_uris << uri
        end
      end
      params = {} if params==nil
      raise OpenTox::BadRequestError.new "params is no hash" unless params.is_a?(Hash)
      params[:validation_uris] = validation_uris.join(",")
      params[:identifier] = identifier.join(",")
      uri = RestClientWrapper.post(File.join($validation[:uri],"/report/algorithm_comparison"), params, waiting_task )
      uri = wait_for_task(uri)
      AlgorithmComparisonReport.new(uri)
    end
  end

end

