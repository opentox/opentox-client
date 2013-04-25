require 'csv'

module OpenTox

  # Ruby wrapper for OpenTox Dataset Webservices (http://opentox.org/dev/apis/api-1.2/dataset).
  class Dataset 

    attr_writer :features, :compounds, :data_entries

    def initialize uri=nil, subjectid=nil
      super uri, subjectid
      @features = []
      @compounds = []
      @data_entries = []
    end

    # Get data (lazy loading from dataset service)

    def metadata force_update=false
      if @metadata.empty? or force_update
        uri = File.join(@uri,"metadata")
        begin
          parse_ntriples RestClientWrapper.get(uri,{},{:accept => "text/plain", :subjectid => @subjectid})
        rescue # fall back to rdfxml
          parse_rdfxml RestClientWrapper.get(uri,{},{:accept => "application/rdf+xml", :subjectid => @subjectid})
        end
        @metadata = @rdf.to_hash[RDF::URI.new(@uri)].inject({}) { |h, (predicate, values)| h[predicate] = values.collect{|v| v.to_s}; h }
      end
      @metadata
    end

    def features force_update=false
      if @features.empty? or force_update
        uri = File.join(@uri,"features")
        uris = RestClientWrapper.get(uri,{},{:accept => "text/uri-list", :subjectid => @subjectid}).split("\n") # ordered datasets return ordered features
        @features = uris.collect{|uri| Feature.new(uri,@subjectid)}
      end
      @features
    end

    def compounds force_update=false
      if @compounds.empty? or force_update
        uri = File.join(@uri,"compounds")
        uris = RestClientWrapper.get(uri,{},{:accept => "text/uri-list", :subjectid => @subjectid}).split("\n") # ordered datasets return ordered compounds
        @compounds = uris.collect{|uri| Compound.new(uri,@subjectid)}
      end
      @compounds
    end
    
    def data_entries force_update=false
      if @data_entries.empty? or force_update
        sparql = "SELECT ?cidx ?fidx ?value FROM <#{uri}> WHERE {
          ?data_entry <#{RDF::OLO.index}> ?cidx ;
                      <#{RDF::OT.values}> ?v .
          ?v          <#{RDF::OT.feature}> ?f;
                      <#{RDF::OT.value}> ?value .
          ?f          <#{RDF::OLO.index}> ?fidx.
          } ORDER BY ?fidx ?cidx" 
          RestClientWrapper.get(service_uri,{:query => sparql},{:accept => "text/uri-list", :subjectid => @subjectid}).split("\n").each do |row|
            r,c,v = row.split("\t")
            @data_entries[r.to_i] ||= []
            @data_entries[r.to_i][c.to_i] = v
          end
        # TODO: fallbacks for external and unordered datasets
        features.each_with_index do |feature,i|
          if feature[RDF.type].include? RDF::OT.NumericFeature
            @data_entries.each { |row| row[i] = row[i].to_f if row[i] }
          end
        end
      end
      @data_entries
    end

    # Find data entry values for a given compound and feature 
    # @param [OpenTox::Compound] Compound 
    # @param [OpenTox::Feature] Feature 
    # @return [Array] Data entry values
    def values(compound, feature)
      rows = (0 ... compounds.length).select { |r| compounds[r].uri == compound.uri }
      col = features.collect{|f| f.uri}.index feature.uri
      rows.collect{|row| data_entries[row][col]}
    end

    # Convenience methods to search by compound/feature URIs

    # Search a dataset for a feature given its URI
    # @param [String] Feature URI
    # @return [OpenTox::Feature] Feature object, or nil if not present
    def find_feature_uri(uri)
      features.select{|f| f.uri == uri}.first
    end

    # Search a dataset for a compound given its URI
    # @param [String] Compound URI
    # @return [OpenTox::Compound] Compound object, or nil if not present
    def find_compound_uri(uri)
      compounds.select{|f| f.uri == uri}.first
    end

    def predictions
      predictions = []
      prediction_feature = nil
      confidence_feature = nil
      metadata[RDF::OT.predictedVariables].each do |uri|
        feature = OpenTox::Feature.new uri, @subjectid
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
          confidence = values(compound,confidence_feature).first
          predictions << {:compound => compound, :value => value, :confidence => confidence} if value and confidence
        end
      end
      predictions
    end

    # Adding data (@features and @compounds are also writable)

    def upload filename, wait=true
      Authorization.check_policy(@uri, @subjectid) if $aa[:uri]
      uri = RestClientWrapper.put(@uri, {:file => File.new(filename)}, {:subjectid => @subjectid})
      wait_for_task uri if URI.task?(uri) and wait
      metadata true 
      @uri
    end

    def add_data_entry compound, feature, value
      @compounds << compound unless @compounds.collect{|c| c.uri}.include?(compound.uri)
      row = @compounds.collect{|c| c.uri}.index(compound.uri)
      @features << feature unless @features.collect{|f| f.uri}.include?(feature.uri)
      col = @features.collect{|f| f.uri}.index(feature.uri)
      @data_entries[row] ||= []
      if @data_entries[row][col] # duplicated values
        #row = @compounds.size
        @compounds << compound
        row = @compounds.collect{|c| c.uri}.rindex(compound.uri)
      end
      @data_entries[row][col] = value
    end

    # TODO: remove? might be dangerous if feature ordering is incorrect
    def << row
      compound = row.shift
      bad_request_error "Dataset features are empty." unless @features
      bad_request_error "Row size '#{row.size}' does not match features size '#{@features.size}'." unless row.size == @features.size
      bad_request_error "First column is not a OpenTox::Compound" unless compound.class == OpenTox::Compound
      @compounds << compound
      @data_entries << row
    end

    # Serialisation

    def to_csv
      CSV.generate do |csv|
        csv << ["SMILES"] + features.collect{|f| f.title}
        compounds.each_with_index do |c,i|
          csv << [c.smiles] + data_entries[i]
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
        @metadata[RDF.type] = RDF::OT.OrderedDataset 
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
          @rdf.each{|statement| writer << statement}
        end
      end

    end

=begin
# TODO: fix bug that affects data_entry positions
    def to_ntriples # redefined string version for better performance

      ntriples = ""
      @metadata[RDF.type] = [ RDF::OT.Dataset, RDF::OT.OrderedDataset ]
      @metadata[RDF.type] ||= eval("RDF::OT."+self.class.to_s.split('::').last)
      @metadata[RDF::DC.date] ||= DateTime.now
      @metadata.each do |predicate,values|
        [values].flatten.each { |value| ntriples << "<#{@uri}> <#{predicate}> '#{value}' .\n" }
      end
      @parameters.each do |parameter|
        p_node = RDF::Node.new.to_s
        ntriples <<  "<#{@uri}> <#{RDF::OT.parameters}> #{p_node} .\n"
        ntriples <<  "#{p_node} <#{RDF.type}> <#{RDF::OT.Parameter}> .\n"
        parameter.each { |k,v| ntriples <<  "#{p_node} <#{k}> '#{v}' .\n" }
      end
      @features.each_with_index do |feature,i|
        ntriples <<  "<#{feature.uri}> <#{RDF.type}> <#{RDF::OT.Feature}> .\n" 
        ntriples <<  "<#{feature.uri}> <#{RDF::OLO.index}> '#{i}' .\n" 
      end
      @compounds.each_with_index do |compound,i|
        ntriples <<  "<#{compound.uri}> <#{RDF.type}> <#{RDF::OT.Compound}> .\n"
        if defined? @neighbors and neighbors.include? compound
          ntriples <<  "<#{compound.uri}> <#{RDF.type}> <#{RDF::OT.Neighbor}> .\n"
        end

        ntriples <<  "<#{compound.uri}> <#{RDF::OLO.index}> '#{i}' .\n"
        data_entry_node = RDF::Node.new
        ntriples <<  "<#{@uri}> <#{RDF::OT.dataEntry}> #{data_entry_node} .\n"
        ntriples <<  "#{data_entry_node} <#{RDF.type}> <#{RDF::OT.DataEntry}> .\n"
        ntriples <<  "#{data_entry_node} <#{RDF::OLO.index}> '#{i}' .\n"
        ntriples <<  "#{data_entry_node} <#{RDF::OT.compound}> <#{compound.uri}> .\n"
        @data_entries[i].each_with_index do |value,j|
          value_node = RDF::Node.new
          ntriples <<  "#{data_entry_node} <#{RDF::OT.values}> #{value_node} .\n"
          ntriples <<  "#{value_node} <#{RDF::OT.feature}> <#{@features[j].uri}> .\n"
          ntriples <<  "#{value_node} <#{RDF::OT.value}> '#{value}' .\n"
        end
      end
      ntriples

    end
=end

    # Methods for for validation service
    
    def split( compound_indices, feats, metadata, subjectid=nil)
      
      bad_request_error "Dataset.split : Please give compounds as indices" if compound_indices.size==0 or !compound_indices[0].is_a?(Fixnum)
      bad_request_error "Dataset.split : Please give features as feature objects (given: #{feats})" if feats!=nil and feats.size>0 and !feats[0].is_a?(OpenTox::Feature)
      dataset = OpenTox::Dataset.new(nil, subjectid)
      dataset.metadata = metadata
      dataset.features = (feats ? feats : self.features)
      compound_indices.each do |c_idx|
        dataset << [ self.compounds[c_idx] ] + dataset.features.each_with_index.collect{|f,f_idx| self.data_entries[c_idx][f_idx]} 
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
    # @param [OpenTox::Dataset] dataset that should be mapped to this dataset (fully loaded)
    # @param [Fixnum] compound_index, corresponding to dataset
    def compound_index( dataset, compound_index )
      unless defined?(@index_map) and @index_map[dataset.uri]
        map = {}
        dataset.compounds.collect{|c| c.uri}.uniq.each do |compound|
          self_indices = compound_indices(compound)
          next unless self_indices
          dataset_indices = dataset.compound_indices(compound)
          if self_indices.size==1  
            dataset_indices.size.times do |i|
              map[dataset_indices[i]] = self_indices[0]
            end
          elsif self_indices.size==dataset_indices.size
            # we do assume that the order is preseverd!
            dataset_indices.size.times do |i|
              map[dataset_indices[i]] = self_indices[i]
            end
          else
            raise "cannot map compound #{compound} from dataset #{dataset.uri} to dataset #{uri}, "+
              "compound occurs #{dataset_indices.size} times and #{self_indices.size} times"
          end
        end  
        @index_map = {} unless defined?(@index_map)
        @index_map[dataset.uri] = map
      end
      @index_map[dataset.uri][compound_index]
    end    
    
    def compound_indices( compound )
      unless defined?(@cmp_indices) and @cmp_indices.has_key?(compound)
        @cmp_indices = {}
        @compounds.size.times do |i|
          c = @compounds[i].uri
          if @cmp_indices[c]==nil
            @cmp_indices[c] = [i]
          else
            @cmp_indices[c] = @cmp_indices[c]+[i]
          end   
        end
      end
      @cmp_indices[compound]
    end
    
    def data_entry_value(compound_index, feature_uri)
      data_entries(true) if @data_entries.empty?
      col = @features.collect{|f| f.uri}.index feature_uri
      @data_entries[compound_index] ?  @data_entries[compound_index][col] : nil
    end
  end

end
