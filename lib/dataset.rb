module OpenTox
  
  # Ruby wrapper for OpenTox Dataset Webservices (http://opentox.org/dev/apis/api-1.2/dataset).
  # TODO: fix API Doc
  class Dataset 

    #include OpenTox

    #attr_reader :features, :compounds, :data_entries, :metadata

    # Create dataset with optional URI. Does not load data into the dataset - you will need to execute one of the load_* methods to pull data from a service or to insert it from other representations.
    # @example Create an empty dataset
    #   dataset = OpenTox::Dataset.new
    # @example Create an empty dataset with URI
    #   dataset = OpenTox::Dataset.new("http:://webservices.in-silico/ch/dataset/1")
    # @param [optional, String] uri Dataset URI
    # @return [OpenTox::Dataset] Dataset object
    def initialize(uri=nil,subjectid=nil)
      super uri, subjectid
      @features = {}
      @compounds = []
      @data_entries = {}
    end

=begin
    # Load YAML representation into the dataset
    # @param [String] yaml YAML representation of the dataset
    # @return [OpenTox::Dataset] Dataset object with YAML data
    def self.from_yaml service_uri, yaml, subjectid=nil
      Dataset.create(service_uri, subjectid).post yaml, :content_type => "application/x-yaml"
    end

    # Load RDF/XML representation from a file
    # @param [String] file File with RDF/XML representation of the dataset
    # @return [OpenTox::Dataset] Dataset object with RDF/XML data
    def self.from_rdfxml service_uri, rdfxml, subjectid=nil
      Dataset.create(service_uri, subjectid).post rdfxml, :content_type => "application/rdf+xml"
    end

    # Load CSV string (format specification: http://toxcreate.org/help)
    # - loads data_entries, compounds, features
    # - sets metadata (warnings) for parser errors
    # - you will have to set remaining metadata manually
    # @param [String] csv CSV representation of the dataset
    # @return [OpenTox::Dataset] Dataset object with CSV data
    def self.from_csv service_uri, csv, subjectid=nil
      Dataset.from_file(service_uri, csv, subjectid)
    end

    # Load Spreadsheet book (created with roo gem http://roo.rubyforge.org/, excel format specification: http://toxcreate.org/help)
    # - loads data_entries, compounds, features
    # - sets metadata (warnings) for parser errors
    # - you will have to set remaining metadata manually
    # @param [Excel] book Excel workbook object (created with roo gem)
    # @return [OpenTox::Dataset] Dataset object with Excel data
    def self.from_xls service_uri, xls, subjectid=nil
      Dataset.create(service_uri, subjectid).post xls, :content_type => "application/vnd.ms-excel"
    end
    
    def self.from_sdf service_uri, sdf, subjectid=nil
      Dataset.create(service_uri, subjectid).post sdf, :content_type => 'chemical/x-mdl-sdfile'
    end
=end

    # Load all data (metadata, data_entries, compounds and features) from URI
    # TODO: move to opentox-server
    def data_entries reload=true
      if reload
        file = Tempfile.new("ot-rdfxml")
        file.puts get :accept => "application/rdf+xml"
        file.close
        to_delete = file.path
            
        data = {}
        feature_values = {}
        feature = {}
        feature_accept_values = {}
        other_statements = {}
        `rapper -i rdfxml -o ntriples #{file.path} 2>/dev/null`.each_line do |line|
          triple = line.chomp.split(' ',3)
          triple = triple[0..2].collect{|i| i.sub(/\s+.$/,'').gsub(/[<>"]/,'')}
          case triple[1] 
          when /#{RDF::OT.values}|#{RDF::OT1.values}/i
            data[triple[0]] = {:compound => "", :values => []} unless data[triple[0]]
            data[triple[0]][:values] << triple[2]  
          when /#{RDF::OT.value}|#{RDF::OT1.value}/i
            feature_values[triple[0]] = triple[2] 
          when /#{RDF::OT.compound}|#{RDF::OT1.compound}/i
            data[triple[0]] = {:compound => "", :values => []} unless data[triple[0]]
            data[triple[0]][:compound] = triple[2]
          when /#{RDF::OT.feature}|#{RDF::OT1.feature}/i
            feature[triple[0]] = triple[2]
          when /#{RDF.type}/i
            if triple[2]=~/#{RDF::OT.Compound}|#{RDF::OT1.Compound}/i and !data[triple[0]]
              data[triple[0]] = {:compound => triple[0], :values => []} 
            end
          when /#{RDF::OT.acceptValue}|#{RDF::OT1.acceptValue}/i # acceptValue in ambit datasets is only provided in dataset/<id> no in dataset/<id>/features  
            feature_accept_values[triple[0]] = [] unless feature_accept_values[triple[0]]
            feature_accept_values[triple[0]] << triple[2]
          else 
          end
        end
        File.delete(to_delete) if to_delete
        data.each do |id,entry|
          if entry[:values].size==0
            # no feature values add plain compounds
            @compounds << entry[:compound] unless @compounds.include? entry[:compound]
          else
            entry[:values].each do |value_id|
              if feature_values[value_id]
                split = feature_values[value_id].split(/\^\^/)
                case split[-1]
                when RDF::XSD.double, RDF::XSD.float 
                  value = split.first.to_f
                when RDF::XSD.boolean
                  value = split.first=~/(?i)true/ ? true : false                
                else
                  value = split.first
                end
              end
              @compounds << entry[:compound] unless @compounds.include? entry[:compound]
              @features[feature[value_id][value_id]] = {}  unless @features[feature[value_id]]
              @data_entries[entry[:compound].to_s] = {} unless @data_entries[entry[:compound].to_s]
              @data_entries[entry[:compound].to_s][feature[value_id]] = [] unless @data_entries[entry[:compound]][feature[value_id]]
              @data_entries[entry[:compound].to_s][feature[value_id]] << value if value!=nil
            end
          end
        end
        features subjectid
        #feature_accept_values.each do |feature, values|
          #self.features[feature][OT.acceptValue] = values
        #end
        self.metadata = metadata(subjectid)
      end
      @data_entries
    end

    # Load and return only compound URIs from the dataset service
    # @return [Array]  Compound URIs in the dataset
    def compounds reload=true
      reload ? @compounds = Compound.all(File.join(@uri,"compounds")) : @compounds
    end

    # Load and return only features from the dataset service
    # @return [Hash]  Features of the dataset
    def features reload=true
      reload ? @features = Feature.all(File.join(@uri,"features")) : @features
    end

=begin
    # returns the accept_values of a feature, i.e. the classification domain / all possible feature values 
    # @param [String] feature the URI of the feature
    # @return [Array] return array with strings, nil if value is not set (e.g. when feature is numeric)
    def accept_values(feature)
      load_features
      accept_values = features[feature][OT.acceptValue]
      accept_values.sort if accept_values
      accept_values
    end

    # Detect feature type(s) in the dataset
    # @return [String] `classification", "regression", "mixed" or unknown`
    def feature_type
      load_features
      feature_types = @features.collect{|f,metadata| metadata[RDF.type]}.flatten.uniq
      if feature_types.include?(OT.NominalFeature)
        "classification"
      elsif feature_types.include?(OT.NumericFeature)
        "regression"
      else
        "unknown"
      end
    end
=end

    # Get Excel representation (alias for to_spreadsheet)
    # @return [Spreadsheet::Workbook] Workbook which can be written with the spreadsheet gem (data_entries only, metadata will will be discarded))
    def to_xls
      get :accept => "application/vnd.ms-excel"
    end

    # Get CSV string representation (data_entries only, metadata will be discarded)
    # @return [String] CSV representation
    def to_csv
      get :accept => "text/csv"
    end

    def to_sdf
      get :accept => 'chemical/x-mdl-sdfile'
    end


    # Get OWL-DL in ntriples format
    # @return [String] N-Triples representation
    def to_ntriples
      get :accept => "application/rdf+xml"
    end

    # Get OWL-DL in RDF/XML format
    # @return [String] RDF/XML representation
    def to_rdfxml
      get :accept => "application/rdf+xml"
    end

    # Get name (DC.title) of a feature
    # @param [String] feature Feature URI
    # @return [String] Feture title
    def feature_name(feature)
      features[feature][DC.title]
    end

    def title
      metadata[DC.title]
    end

    # Insert a statement (compound_uri,feature_uri,value)
    # @example Insert a statement (compound_uri,feature_uri,value)
    #   dataset.add "http://webservices.in-silico.ch/compound/InChI=1S/C6Cl6/c7-1-2(8)4(10)6(12)5(11)3(1)9", "http://webservices.in-silico.ch/dataset/1/feature/hamster_carcinogenicity", true
    # @param [String] compound Compound URI
    # @param [String] feature Compound URI
    # @param [Boolean,Float] value Feature value
    def add (compound,feature,value)
      @compounds << compound unless @compounds.include? compound
      @features[feature] = {}  unless @features[feature]
      @data_entries[compound] = {} unless @data_entries[compound]
      @data_entries[compound][feature] = [] unless @data_entries[compound][feature]
      @data_entries[compound][feature] << value if value!=nil
    end

    # Add a feature
    # @param [String] feature Feature URI
    # @param [Hash] metadata Hash with feature metadata
    def add_feature(feature,metadata={})
      @features[feature] = metadata
    end

    # Add/modify metadata for a feature
    # @param [String] feature Feature URI
    # @param [Hash] metadata Hash with feature metadata
    def add_feature_metadata(feature,metadata)
      metadata.each { |k,v| @features[feature][k] = v }
    end
    
    # Add a new compound
    # @param [String] compound Compound URI
    def add_compound (compound)
      @compounds << compound unless @compounds.include? compound
    end
    
    # Creates a new dataset, by splitting the current dataset, i.e. using only a subset of compounds and features
    # @param [Array] compounds List of compound URIs
    # @param [Array] features List of feature URIs
    # @param [Hash] metadata Hash containing the metadata for the new dataset
    # @param [String] subjectid
    # @return [OpenTox::Dataset] newly created dataset, already saved
    def split( compounds, features, metadata)
      LOGGER.debug "split dataset using "+compounds.size.to_s+"/"+@compounds.size.to_s+" compounds"
      raise "no new compounds selected" unless compounds and compounds.size>0
      dataset = OpenTox::Dataset.create(CONFIG[:services]["opentox-dataset"],@subjectid)
      if features.size==0
        compounds.each{ |c| dataset.add_compound(c) }
      else
        compounds.each do |c|
          features.each do |f|
            if @data_entries[c]==nil or @data_entries[c][f]==nil
              dataset.add(c,f,nil)
            else
              @data_entries[c][f].each do |v|
                dataset.add(c,f,v)
              end
            end
          end
        end
      end
      # set feature metadata in new dataset accordingly (including accept values)      
      features.each do |f|
        self.features[f].each do |k,v|
          dataset.features[f][k] = v
        end
      end
      dataset.add_metadata(metadata)
      dataset.save
      dataset
    end

    # Save dataset at the dataset service 
    # - creates a new dataset if uri is not set
    # - overwrites dataset if uri exists
    # @return [String] Dataset URI
    def save
      @compounds.uniq!
      # create dataset if uri is empty
      self.uri = RestClientWrapper.post(CONFIG[:services]["opentox-dataset"],{:subjectid => @subjectid}).to_s.chomp unless @uri
      if (CONFIG[:yaml_hosts].include?(URI.parse(@uri).host))
        RestClientWrapper.post(@uri,self.to_yaml,{:content_type =>  "application/x-yaml", :subjectid => @subjectid})
      else
        s = Serializer::Owl.new
        s.add_dataset(self)
        RestClientWrapper.post(@uri, s.to_rdfxml,{:content_type => "application/rdf+xml" , :subjectid => @subjectid})
      end
      @uri
    end

    private
    # Copy a dataset (rewrites URI)
    def copy(dataset)
      @metadata = dataset.metadata
      @data_entries = dataset.data_entries
      @compounds = dataset.compounds
      @features = dataset.features
      if @uri
        self.uri = @uri 
      else
        @uri = dataset.metadata[XSD.anyURI]
      end
    end
  end
end
