module OpenTox

  # Ruby wrapper for OpenTox Dataset Webservices (http://opentox.org/dev/apis/api-1.2/dataset).
  class Dataset 

    attr_accessor :features, :compounds, :data_entries

    def initialize uri=nil, subjectid=nil
      super uri, subjectid
      @features = []
      @compounds = []
      @data_entries = []
      append RDF.type, RDF::OT.OrderedDataset
    end

    def upload filename, wait=true
      uri = RestClientWrapper.put(@uri, {:file => File.new(filename)}, {:subjectid => @subjectid})
      OpenTox::Task.new(uri).wait if URI.task?(uri) and wait
    end

    def to_csv
      CSV.generate do |csv|
        csv << ["SMILES"] + @features.collect{|f| f.title}
        @compounds.each_with_index do |c,i|
          csv << [c.smiles] + @data_entries[i]
        end
      end
    end

    def get(force_no_backend_query=false)
      have_rdf = (force_no_backend_query and @rdf.size>0)
      ordered = (have_rdf or OpenTox::Dataset.ordered?(@uri))
      super() if (!have_rdf and !ordered)
      @features = []
      @compounds = []
      @data_entries = []

      # AM: read ordered dataset from RDF
      if ordered

        # Read only some data as rdf
        unless have_rdf
          self.parse_rdfxml( RestClient.get([@uri,"allnde"].join("/"),{:accept => "application/rdf+xml"}), true )
        end

        # Features
        @features = self.find_features_rdf
        numeric_features = @features.collect{|f| 
          f.get
          f[RDF.type].include?(RDF::OT.NumericFeature) or f[RDF.type].include?(RDF::OT.Substructure)
        }

        # Compounds
        if have_rdf
          @compounds = self.find_compounds_rdf
        else
          @compounds = RestClient.get([@uri,"compounds"].join("/"),{:accept => "text/uri-list"}).split("\n").collect { |cmpd| OpenTox::Compound.new cmpd }
        end

        # Data Entries
        if have_rdf
          table = self.find_data_entries_rdf
        else
          values = OpenTox::Dataset.find_data_entries_sparql(@uri)
          table = values + Array.new(@compounds.size*@features.size-values.size, "")
        end
        
        clim=(@compounds.size-1)
        cidx = fidx = 0
        num=numeric_features[fidx]
        @data_entries = (Array.new(@compounds.size*@features.size)).each_slice(@features.size).to_a # init to nil
        table.each { |val|
          unless val.blank?
            @data_entries[cidx][fidx] = (num ? val.to_f : val)
          end
          if (cidx < clim)
            cidx+=1
          else
            cidx=0
            fidx+=1
            num=numeric_features[fidx]
          end
        }

      # AM: read unordered dataset from RDF
      else
        query = RDF::Query.new do
          pattern [:uri, RDF.type, RDF::OT.Feature]
        end
        @features = query.execute(@rdf).collect{|s| OpenTox::Feature.new(s.uri.to_s)}
        query = RDF::Query.new do
          pattern [:data_entry, RDF::OT.compound, :compound]
        end
        @compounds = query.execute(@rdf).sort_by{|s| s.data_entry}.collect{|s| OpenTox::Compound.new s.compound.to_s}
        numeric_features = @features.collect{|f| f.get; f[RDF.type].include? RDF::OT.NumericFeature}
        @compounds.each do |compound|
          values = []
          @features.each_with_index do |feature,i|
            query = RDF::Query.new do
              pattern [:data_entry, RDF::OT.compound, RDF::URI.new(compound.uri)]
              pattern [:data_entry, RDF::OT.values, :values]
              pattern [:values, RDF::OT.feature, RDF::URI.new(feature.uri)]
              pattern [:values, RDF::OT.value, :value]
            end
            value = query.execute(@rdf).first.value.to_s
            value = value.to_f if numeric_features[i] and !value.nil?
            values << value
          end
          @data_entries << values
        end
      end
    end

    def get_metadata
      uri = File.join(@uri,"metadata")
      begin
        parse_ntriples RestClientWrapper.get(uri,{},{:accept => "text/plain", :subjectid => @subjectid})
      rescue # fall back to rdfxml
        parse_rdfxml RestClientWrapper.get(uri,{},{:accept => "application/rdf+xml", :subjectid => @subjectid})
      end
      metadata
    end

    def << data_entry
      compound = data_entry.shift
      bad_request_error "Dataset features are empty." unless features
      bad_request_error "data_entry size '#{data_entry.size}' does not match features size '#{features.size}'." unless data_entry.size == features.size
      bad_request_error "First data_entry is not a OpenTox::Compound" unless compound.class == OpenTox::Compound
      @compounds << compound
      @data_entries << data_entry
    end

    RDF_FORMATS.each do |format|

      # redefine rdf serialization methods 
      send :define_method, "to_#{format}".to_sym do
        # TODO: check, might affect appending to unordered datasets
        features.each_with_index do |feature,i|
          @rdf << [RDF::URI.new(feature.uri), RDF::URI.new(RDF.type), RDF::URI.new(RDF::OT.Feature)] 
          @rdf << [RDF::URI.new(feature.uri), RDF::URI.new(RDF::OLO.index), RDF::Literal.new(i)] 
        end
        compounds.each_with_index do |compound,i|
          @rdf << [RDF::URI.new(compound.uri), RDF::URI.new(RDF.type), RDF::URI.new(RDF::OT.Compound)]
          @rdf << [RDF::URI.new(compound.uri), RDF::URI.new(RDF::OLO.index), RDF::Literal.new(i)]
          data_entry_node = RDF::Node.new
          @rdf << [RDF::URI.new(@uri), RDF::URI.new(RDF::OT.dataEntry), data_entry_node]
          @rdf << [data_entry_node, RDF::URI.new(RDF.type), RDF::URI.new(RDF::OT.DataEntry)]
          @rdf << [data_entry_node, RDF::URI.new(RDF::OLO.index), RDF::Literal.new(i)]
          @rdf << [data_entry_node, RDF::URI.new(RDF::OT.compound), RDF::URI.new(compound.uri)]
          data_entries[i].each_with_index do |value,j|
            value_node = RDF::Node.new
            @rdf << [data_entry_node, RDF::URI.new(RDF::OT.values), value_node]
            @rdf << [value_node, RDF::URI.new(RDF::OT.feature), RDF::URI.new(@features[j].uri)]
            @rdf << [value_node, RDF::URI.new(RDF::OT.value), RDF::Literal.new(value)]
          end
        end
        super()
      end

    end
  end
end
