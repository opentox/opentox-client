require 'csv'

module OpenTox

  # Ruby wrapper for OpenTox Dataset Webservices (http://opentox.org/dev/apis/api-1.2/dataset).
  class Dataset

    attr_writer :features, :compounds, :data_entries

    def initialize uri=nil
      super uri
      @features = []
      @compounds = []
      @data_entries = []
    end

    # Get data (lazy loading from dataset service)
    # overrides {OpenTox#metadata} to only load the metadata instead of the whole dataset
    # @return [Hash] the metadata
    def metadata force_update=false
      if @metadata.empty? or force_update
        uri = File.join(@uri,"metadata")
        begin
          parse_ntriples RestClientWrapper.get(uri,{},{:accept => "text/plain"})
        rescue # fall back to rdfxml
          parse_rdfxml RestClientWrapper.get(uri,{},{:accept => "application/rdf+xml"})
        end
        @metadata = @rdf.to_hash[RDF::URI.new(@uri)].inject({}) { |h, (predicate, values)| h[predicate] = values.collect{|v| v.to_s}; h }
      end
      @metadata
    end

    # @return [Array] feature objects (NOT uris)
    def features force_update=false
      if @features.empty? or force_update
        uri = File.join(@uri,"features")
        begin
          uris = RestClientWrapper.get(uri,{},{:accept => "text/uri-list"}).split("\n") # ordered datasets return ordered features
        rescue
          uris = []
        end
        @features = uris.collect{|uri| Feature.new(uri)}
      end
      @features
    end

    # @return [Array] compound objects (NOT uris)
    def compounds force_update=false
      if @compounds.empty? or force_update
        uri = File.join(@uri,"compounds")
        begin
          uris = RestClientWrapper.get(uri,{},{:accept => "text/uri-list"}).split("\n") # ordered datasets return ordered compounds
        rescue
          uris = []
        end
        @compounds = uris.collect{|uri| Compound.new(uri)}
      end
      @compounds
    end

    # @return [Array] with two dimensions,
    #   first index: compounds, second index: features, values: compound feature values
    def data_entries force_update=false
      if @data_entries.empty? or force_update
        sparql = "SELECT ?cidx ?fidx ?value FROM <#{uri}> WHERE {
          ?data_entry <#{RDF::OLO.index}> ?cidx ;
                      <#{RDF::OT.values}> ?v .
          ?v          <#{RDF::OT.feature}> ?f;
                      <#{RDF::OT.value}> ?value .
          ?f          <#{RDF::OLO.index}> ?fidx.
          } ORDER BY ?fidx ?cidx"
          RestClientWrapper.get(service_uri,{:query => sparql},{:accept => "text/uri-list"}).split("\n").each do |row|
            r,c,v = row.split("\t")
            @data_entries[r.to_i] ||= []
            # adjust value class depending on feature type, StringFeature takes precedence over NumericFeature
            if features[c.to_i][RDF.type].include? RDF::OT.NumericFeature and ! features[c.to_i][RDF.type].include? RDF::OT.StringFeature
              v = v.to_f if v
            end
            @data_entries[r.to_i][c.to_i] = v if v
          end
        # TODO: fallbacks for external and unordered datasets
      end
      @data_entries
    end

    # Find data entry values for a given compound and feature
    # @param compound [OpenTox::Compound] OpenTox Compound object
    # @param feature [OpenTox::Feature] OpenTox Feature object
    # @return [Array] Data entry values
    def values(compound, feature)
      rows = (0 ... compounds.length).select { |r| compounds[r].uri == compound.uri }
      col = features.collect{|f| f.uri}.index feature.uri
      rows.collect{|row| data_entries[row][col]}
    end

    # Convenience methods to search by compound/feature URIs

    # Search a dataset for a feature given its URI
    # @param uri [String] Feature URI
    # @return [OpenTox::Feature] Feature object, or nil if not present
    def find_feature_uri(uri)
      features.select{|f| f.uri == uri}.first
    end

    # Search a dataset for a compound given its URI
    # @param uri [String] Compound URI
    # @return [OpenTox::Compound] Compound object, or nil if not present
    def find_compound_uri(uri)
      compounds.select{|f| f.uri == uri}.first
    end

    # for prediction result datasets
    # assumes that there are features with title prediction and confidence
    # @return [Array] of Hashes with keys { :compound, :value ,:confidence } (compound value is object not uri)
    def predictions
      predictions = []
      prediction_feature = nil
      confidence_feature = nil
      metadata[RDF::OT.predictedVariables].each do |uri|
        feature = OpenTox::Feature.new uri
        case feature.title
        when /prediction$/
          prediction_feature = feature
        when /confidence$/
          confidence_feature = feature
        end
      end
      if prediction_feature and confidence_feature
        compounds.each do |compound|
          value = values(compound,prediction_feature).first
          value = value.to_f if prediction_feature[RDF.type].include? RDF::OT.NumericFeature and ! prediction_feature[RDF.type].include? RDF::OT.StringFeature
          confidence = values(compound,confidence_feature).first.to_f
          predictions << {:compound => compound, :value => value, :confidence => confidence} if value and confidence
        end
      end
      predictions
    end

    # Adding data methods
    # (Alternatively, you can directly change @features and @compounds)

    # Create a dataset from file (csv,sdf,...)
    # @param filename [String]
    # @return [String] dataset uri
    def upload filename, wait=true
      uri = RestClientWrapper.put(@uri, {:file => File.new(filename)})
      wait_for_task uri if URI.task?(uri) and wait
      compounds true
      features true
      metadata true
      @uri
    end

    # @param compound [OpenTox::Compound]
    # @param feature [OpenTox::Feature]
    # @param value [Object] (will be converted to String)
    # @return [Array] data_entries
    def add_data_entry compound, feature, value
      @compounds << compound unless @compounds.collect{|c| c.uri}.include?(compound.uri)
      row = @compounds.collect{|c| c.uri}.index(compound.uri)
      @features << feature unless @features.collect{|f| f.uri}.include?(feature.uri)
      col = @features.collect{|f| f.uri}.index(feature.uri)
      if @data_entries[row] and @data_entries[row][col] # duplicated values
        @compounds << compound
        row = @compounds.collect{|c| c.uri}.rindex(compound.uri)
      end
      if value
        @data_entries[row] ||= []
        @data_entries[row][col] = value
      end
    end

    # TODO: remove? might be dangerous if feature ordering is incorrect
    # MG: I would not remove this because add_data_entry is very slow (4 times searching in arrays)
    # CH: do you have measurements? compound and feature arrays are not that big, I suspect that feature search/creation is the time critical step
    # @param row [Array]
    # @example
    #   d = Dataset.new
    #   d.features << Feature.new(a)
    #   d.features << Feature.new(b)
    #   d << [ Compound.new("c1ccccc1"), feature-value-a, feature-value-b ]
    def << row
      compound = row.shift # removes the compound from the array
      bad_request_error "Dataset features are empty." unless @features
      bad_request_error "Row size '#{row.size}' does not match features size '#{@features.size}'." unless row.size == @features.size
      bad_request_error "First column is not a OpenTox::Compound" unless compound.class == OpenTox::Compound
      @compounds << compound
      @data_entries << row
    end

    # Serialisation

    # converts dataset to csv format including compound smiles as first column, other column headers are feature titles
    # @return [String]
    def to_csv(inchi=false)
      CSV.generate() do |csv| #{:force_quotes=>true}
        csv << [inchi ? "InChI" : "SMILES"] + features.collect{|f| f.title}
        compounds.each_with_index do |c,i|
          csv << [inchi ? c.inchi : c.smiles] + data_entries[i]
        end
      end
    end

    RDF_FORMATS.each do |format|

      # redefine rdf parse methods for all formats e.g. parse_rdfxml
      send :define_method, "parse_#{format}".to_sym do |rdf|
        # TODO: parse ordered dataset
        # TODO: parse data entries
        # TODO: parse metadata
        @rdf = RDF::Graph.new
        RDF::Reader.for(format).new(rdf) do |reader|
          reader.each_statement{ |statement| @rdf << statement }
        end
        query = RDF::Query.new({ :uri => { RDF.type => RDF::OT.Compound } })
        @compounds = query.execute(@rdf).collect { |solution| OpenTox::Compound.new solution.uri }
        query = RDF::Query.new({ :uri => { RDF.type => RDF::OT.Feature } })
        @features = query.execute(@rdf).collect { |solution| OpenTox::Feature.new solution.uri }
        @compounds.each_with_index do |c,i|
          @features.each_with_index do |f,j|
          end
        end
      end


      # redefine rdf serialization methods
      send :define_method, "to_#{format}".to_sym do
        @metadata[RDF.type] = [RDF::OT.Dataset, RDF::OT.OrderedDataset]
        create_rdf
        @features.each_with_index do |feature,i|
          @rdf << [RDF::URI.new(feature.uri), RDF::URI.new(RDF.type), RDF::URI.new(RDF::OT.Feature)]
          @rdf << [RDF::URI.new(feature.uri), RDF::URI.new(RDF::OLO.index), RDF::Literal.new(i)]
        end
        @compounds.each_with_index do |compound,i|
          @rdf << [RDF::URI.new(compound.uri), RDF::URI.new(RDF.type), RDF::URI.new(RDF::OT.Compound)]
          if defined? @neighbors and neighbors.include? compound
            @rdf << [RDF::URI.new(compound.uri), RDF::URI.new(RDF.type), RDF::URI.new(RDF::OT.Neighbor)]
          end

          @rdf << [RDF::URI.new(compound.uri), RDF::URI.new(RDF::OLO.index), RDF::Literal.new(i)]
          data_entry_node = RDF::Node.new
          @rdf << [RDF::URI.new(@uri), RDF::URI.new(RDF::OT.dataEntry), data_entry_node]
          @rdf << [data_entry_node, RDF::URI.new(RDF.type), RDF::URI.new(RDF::OT.DataEntry)]
          @rdf << [data_entry_node, RDF::URI.new(RDF::OLO.index), RDF::Literal.new(i)]
          @rdf << [data_entry_node, RDF::URI.new(RDF::OT.compound), RDF::URI.new(compound.uri)]
          @data_entries[i].each_with_index do |value,j|
            value_node = RDF::Node.new
            @rdf << [data_entry_node, RDF::URI.new(RDF::OT.values), value_node]
            @rdf << [value_node, RDF::URI.new(RDF::OT.feature), RDF::URI.new(@features[j].uri)]
            @rdf << [value_node, RDF::URI.new(RDF::OT.value), RDF::Literal.new(value)]
          end
        end
        RDF::Writer.for(format).buffer do |writer|
          writer << @rdf
        end
      end

    end

# TODO: fix bug that affects data_entry positions # DG: who wrotes this comment ?
    def to_ntriples # redefined string version for better performance
      ntriples = ""
      @metadata[RDF.type] = [ RDF::OT.Dataset, RDF::OT.OrderedDataset ]
      @metadata.each do |predicate,values|
        [values].flatten.each do |value|
          URI.valid?(value) ? value = "<#{value}>" : value = "\"#{value}\""
          ntriples << "<#{@uri}> <#{predicate}> #{value} .\n" #\n"
        end
      end
      @parameters.each_with_index do |parameter,i|
        p_node = "_:parameter"+ i.to_s
        ntriples <<  "<#{@uri}> <#{RDF::OT.parameters}> #{p_node} .\n"
        ntriples <<  "#{p_node} <#{RDF.type}> <#{RDF::OT.Parameter}> .\n"
        parameter.each { |k,v| ntriples <<  "#{p_node} <#{k}> \"#{v.to_s.tr('"', '\'')}\" .\n" }
      end
      @features.each_with_index do |feature,i|
        ntriples <<  "<#{feature.uri}> <#{RDF.type}> <#{RDF::OT.Feature}> .\n"
        ntriples <<  "<#{feature.uri}> <#{RDF::OLO.index}> \"#{i}\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n" # sorting at dataset service does not work without type information
      end
      @compounds.each_with_index do |compound,i|
        ntriples <<  "<#{compound.uri}> <#{RDF.type}> <#{RDF::OT.Compound}> .\n"
        if defined? @neighbors and neighbors.include? compound
          ntriples <<  "<#{compound.uri}> <#{RDF.type}> <#{RDF::OT.Neighbor}> .\n"
        end

        ntriples <<  "<#{compound.uri}> <#{RDF::OLO.index}> \"#{i}\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n" # sorting at dataset service does not work without type information
        data_entry_node = "_:dataentry"+ i.to_s
        ntriples <<  "<#{@uri}> <#{RDF::OT.dataEntry}> #{data_entry_node} .\n"
        ntriples <<  "#{data_entry_node} <#{RDF.type}> <#{RDF::OT.DataEntry}> .\n"
        ntriples <<  "#{data_entry_node} <#{RDF::OLO.index}> \"#{i}\"^^<http://www.w3.org/2001/XMLSchema#integer> .\n" # sorting at dataset service does not work without type information
        ntriples <<  "#{data_entry_node} <#{RDF::OT.compound}> <#{compound.uri}> .\n"
        @data_entries[i].each_with_index do |value,j|
          value_node = data_entry_node+ "_value"+ j.to_s
          ntriples <<  "#{data_entry_node} <#{RDF::OT.values}> #{value_node} .\n"
          ntriples <<  "#{value_node} <#{RDF::OT.feature}> <#{@features[j].uri}> .\n"
          ntriples <<  "#{value_node} <#{RDF::OT.value}> \"#{value}\" .\n"
        end unless @data_entries[i].nil?
      end
      ntriples

    end

    # Methods for for validation service

    # create a new dataset with the specified compounds and features
    # @param compound_indices [Array] compound indices (integers)
    # @param feats [Array] features objects
    # @param metadata [Hash]
    # @return [OpenTox::Dataset]
    def split( compound_indices, feats, metadata)

      bad_request_error "Dataset.split : Please give compounds as indices" if compound_indices.size==0 or !compound_indices[0].is_a?(Fixnum)
      bad_request_error "Dataset.split : Please give features as feature objects (given: #{feats})" if feats!=nil and feats.size>0 and !feats[0].is_a?(OpenTox::Feature)
      dataset = OpenTox::Dataset.new
      dataset.metadata = metadata
      dataset.features = (feats ? feats : self.features)
      compound_indices.each do |c_idx|
        d = [ self.compounds[c_idx] ]
        dataset.features.each_with_index.each do |f,f_idx|
          d << (self.data_entries[c_idx] ? self.data_entries[c_idx][f_idx] : nil)
        end
        dataset << d
      end
      dataset.put
      dataset
    end


    # maps a compound-index from another dataset to a compound-index from this dataset
    # mapping works as follows:
    # (compound c is the compound identified by the compound-index of the other dataset)
    # * c occurs only once in this dataset? map compound-index of other dataset to index in this dataset
    # * c occurs >1 in this dataset?
    # ** number of occurences is equal in both datasets? assume order is preserved(!) and map accordingly
    # ** number of occurences is not equal in both datasets? cannot map, raise error
    # @param dataset [OpenTox::Dataset] dataset that should be mapped to this dataset (fully loaded)
    # @param compound_index [Fixnum], corresponding to dataset
    def compound_index( dataset, compound_index )
      compound_uri = dataset.compounds[compound_index].uri
      self_indices = compound_indices(compound_uri)
      if self_indices==nil
        nil
      else
        dataset_indices = dataset.compound_indices(compound_uri)
        if self_indices.size==1
          self_indices.first
        elsif self_indices.size==dataset_indices.size
          # we do assume that the order is preseverd (i.e., the nth occurences in both datasets are mapped to each other)!
          self_indices[dataset_indices.index(compound_index)]
        else
          raise "cannot map compound #{compound} from dataset #{dataset.uri} to dataset #{uri}, "+
            "compound occurs #{dataset_indices.size} times and #{self_indices.size} times"
        end
      end
    end

    # returns the inidices of the compound in the dataset
    # @param compound_uri [String]
    # @return [Array] compound index (position) of the compound in the dataset, array-size is 1 unless multiple occurences
    def compound_indices( compound_uri )
      unless defined?(@cmp_indices) and @cmp_indices.has_key?(compound_uri)
        @cmp_indices = {}
        compounds().size.times do |i|
          c = @compounds[i].uri
          if @cmp_indices[c]==nil
            @cmp_indices[c] = [i]
          else
            @cmp_indices[c] = @cmp_indices[c]+[i]
          end
        end
      end
      @cmp_indices[compound_uri]
    end

    # returns compound feature value using the compound-index and the feature_uri
    def data_entry_value(compound_index, feature_uri)
      data_entries(true) if @data_entries.empty?
      col = @features.collect{|f| f.uri}.index feature_uri
      @data_entries[compound_index] ?  @data_entries[compound_index][col] : nil
    end
  end

end
