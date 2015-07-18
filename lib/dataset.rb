require 'csv'

module OpenTox

  # Ruby wrapper for OpenTox Dataset Webservices (http://opentox.org/dev/apis/api-1.2/dataset).
  class Dataset
      include Mongoid::Document

    field :feature_ids, type: Array
    field :inchis, type: Array
    field :data_entries, type: Array
    field :warnings, type: Array
    field :source, type: String

    def initialize
      super
      self.feature_ids = []
      self.inchis = []
      self.data_entries = []
      self.warnings = []
    end

    # Readers

    def compounds
      inchis.collect{|i| OpenTox::Compound.new i}
    end

    def features
      self.feature_ids.collect{|id| OpenTox::Feature.find(id)}
    end

    # Writers

    def compounds=(compounds)
      self.inchis = compounds.collect{|c| c.inchi}
    end

    def add_compound(compound)
      self.inchis << compound.id
    end

    def features=(features)
      self.feature_ids = features.collect{|f| f.id}
    end

    def add_feature(feature)
      self.feature_ids << feature.id
    end

    # Find data entry values for a given compound and feature
    # @param compound [OpenTox::Compound] OpenTox Compound object
    # @param feature [OpenTox::Feature] OpenTox Feature object
    # @return [Array] Data entry values
    def values(compound, feature)
      rows = (0 ... inchis.length).select { |r| inchis[r].uri == compound.uri }
      col = feature_ids.collect{|f| f.uri}.index feature.uri
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
    # assumes that there are feature_ids with title prediction and confidence
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
    # (Alternatively, you can directly change @data["feature_ids"] and @data["compounds"])

    # Create a dataset from file (csv,sdf,...)
    # @param filename [String]
    # @return [String] dataset uri
    def upload filename, wait=true
      self.title = File.basename(filename)
      self.source = filename
      table = CSV.read filename, :skip_blanks => true
      from_table table
      save
    end

    # @param compound [OpenTox::Compound]
    # @param feature [OpenTox::Feature]
    # @param value [Object] (will be converted to String)
    # @return [Array] data_entries
    def add_data_entry compound, feature, value
      @data["compounds"] << compound unless @data["compounds"].collect{|c| c.uri}.include?(compound.uri)
      row = @data["compounds"].collect{|c| c.uri}.index(compound.uri)
      @data["features"] << feature unless @data["features"].collect{|f| f.uri}.include?(feature.uri)
      col = @data["features"].collect{|f| f.uri}.index(feature.uri)
      if @data["data_entries"][row] and @data["data_entries"][row][col] # duplicated values
        @data["compounds"] << compound
        row = @data["compounds"].collect{|c| c.uri}.rindex(compound.uri)
      end
      if value
        @data["data_entries"][row] ||= []
        @data["data_entries"][row][col] = value
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
      bad_request_error "Dataset features are empty." unless feature_ids
      bad_request_error "Row size '#{row.size}' does not match features size '#{feature_ids.size}'." unless row.size == feature_ids.size
      bad_request_error "First column is not a OpenTox::Compound" unless compound.class == OpenTox::Compound
      self.inchis << compound.inchi
      self.data_entries << row
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
      compound_inchi = dataset.compounds[compound_index].inchi
      self_indices = compound_indices(compound_inchi)
      if self_indices==nil
        nil
      else
        dataset_indices = dataset.compound_indices(compound_inchi)
        if self_indices.size==1
          self_indices.first
        elsif self_indices.size==dataset_indices.size
          # we do assume that the order is preseverd (i.e., the nth occurences in both datasets are mapped to each other)!
          self_indices[dataset_indices.index(compound_index)]
        else
          raise "cannot map compound #{compound_inchi} from dataset #{dataset.id} to dataset #{self.id}, "+
            "compound occurs #{dataset_indices.size} times and #{self_indices.size} times"
        end
      end
    end

    # returns the inidices of the compound in the dataset
    # @param compound_inchi [String]
    # @return [Array] compound index (position) of the compound in the dataset, array-size is 1 unless multiple occurences
    def compound_indices( compound_inchi )
      unless defined?(@cmp_indices) and @cmp_indices.has_key?(compound_inchi)
        @cmp_indices = {}
        compounds().size.times do |i|
          c = self.compounds[i].inchi
          if @cmp_indices[c]==nil
            @cmp_indices[c] = [i]
          else
            @cmp_indices[c] = @cmp_indices[c]+[i]
          end
        end
      end
      @cmp_indices[compound_inchi]
    end

    # returns compound feature value using the compound-index and the feature_uri
    def data_entry_value(compound_index, feature_uri)
      data_entries(true) if @data["data_entries"].empty?
      col = @data["features"].collect{|f| f.uri}.index feature_uri
      @data["data_entries"][compound_index] ?  @data["data_entries"][compound_index][col] : nil
    end

    def from_table table

      # features
      feature_names = table.shift.collect{|f| f.strip}
      self.warnings << "Duplicate features in table header." unless feature_names.size == feature_names.uniq.size
      compound_format = feature_names.shift.strip
      bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: SMILES, InChI." unless compound_format =~ /SMILES|InChI/i
      ignored_feature_indices = []
      numeric = []
      feature_names.each_with_index do |f,i|
        values = table.collect{|row| val=row[i+1].to_s.strip; val.blank? ? nil : val }.uniq.compact
        types = values.collect{|v| v.numeric? ? true : false}.uniq
        metadata = {"title" => f}
        if values.size == 0 # empty feature
        elsif  values.size > 5 and types.size == 1 and types.first == true # 5 max classes
          metadata["numeric"] = true
          numeric[i] = true
        else
          metadata["nominal"] = true
          metadata["string"] = true
          metadata["accept_values"] = values
          numeric[i] = false
        end
        feature = OpenTox::Feature.find_or_create_by metadata
        self.feature_ids << feature.id unless feature.nil?
      end

      # compounds and values
      r = -1
      table.each_with_index do |values,j|
        compound = values.shift
        begin
          case compound_format
          when /SMILES/i
            c = OpenTox::Compound.from_smiles(compound)
            if c.inchi.empty?
              self.warnings << "Cannot parse #{compound_format} compound '#{compound.strip}' at position #{j+2}, all entries are ignored."
              next
            else
              inchi = c.inchi
            end
          when /InChI/i
            # TODO validate inchi
            inchi = compound
          else
            raise "wrong compound format" #should be checked above
          end
        rescue
          self.warnings << "Cannot parse #{compound_format} compound '#{compound}' at position #{j+2}, all entries are ignored."
          next
        end
        
        r += 1
        self.inchis << inchi
        unless values.size == self.feature_ids.size
          self.warnings << "Number of values at position #{j+2} (#{values.size}) is different than header size (#{self.feature_ids.size}), all entries are ignored."
          next
        end

        self.data_entries << []
        values.each_with_index do |v,i|
          if v.blank?
            self.data_entries.last << nil
            self.warnings << "Empty value for compound '#{compound}' (row #{r+2}) and feature '#{feature_names[i]}' (column #{i+2})."
            next
          elsif numeric[i]
            self.data_entries.last << v.to_f
          else
            self.data_entries.last << v.strip
          end
        end
      end
      self.inchis.duplicates.each do |inchi|
        positions = []
        self.inchis.each_with_index{|c,i| positions << i+1 if !c.blank? and c == inchi}
        self.warnings << "Duplicate compound #{inchi} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
      end
    end
  end
end
