require 'csv'
require 'tempfile'

module OpenTox

  class LazarPrediction < Dataset
    field :creator, type: String
  end

  class DescriptorDataset < Dataset
    field :feature_calculation_algorithm, type: String
  end

  class FminerDataset < DescriptorDataset
    field :training_algorithm, type: String
    field :training_dataset_id, type: BSON::ObjectId
    field :training_feature_id, type: BSON::ObjectId
    field :training_parameters, type: Hash
  end

  class Dataset
    include Mongoid::Document

    attr_accessor :bulk
    attr_writer :data_entries

    # associations like has_many, belongs_to deteriorate performance
    field :feature_ids, type: Array, default: []
    field :compound_ids, type: Array, default: []
    field :data_entries_id, type: BSON::ObjectId
    field :source, type: String
    field :warnings, type: Array, default: []

    def initialize params=nil
      super params
      @bulk = []
    end

    def save_all
      dump = Marshal.dump(@data_entries)
      file = Mongo::Grid::File.new(dump, :filename => "#{self.id.to_s}.data_entries")
      data_entries_id = $gridfs.insert_one(file)
      update(:data_entries_id => data_entries_id)
      save
    end

    # Readers

    def compounds
      @compounds ||= self.compound_ids.collect{|id| OpenTox::Compound.find id}
      @compounds
    end

    def features
      @features ||= self.feature_ids.collect{|id| OpenTox::Feature.find(id)}
      @features
    end

    def fill_nil_with n
      (0 .. compound_ids.size-1).each do |i|
        @data_entries[i] ||= []
        (0 .. feature_ids.size-1).each do |j|
          @data_entries[i][j] ||= n
        end
      end
    end

    def [](row,col)
      @data_entries[row,col]
    end

    def []=(row,col,v)
      @data_entries ||= []
      @data_entries[row] ||= []
      @data_entries[row][col] = v
    end

    # merge dataset (i.e. append features)
    def +(dataset)
      bad_request_error "Dataset merge failed because the argument is not a OpenTox::Dataset but a #{dataset.class}" unless dataset.is_a? Dataset
      bad_request_error "Dataset merge failed because compounds are unequal in datasets #{self.id} and #{dataset.id}" unless compound_ids == dataset.compound_ids
      self.feature_ids ||= []
      self.feature_ids = self.feature_ids + dataset.feature_ids
      @data_entries ||= Array.new(compound_ids.size){[]}
      @data_entries.each_with_index do |row,i|
        @data_entries[i] = row + dataset.fingerprint(compounds[i])
      end
      self

    end

    def fingerprint(compound)
      data_entries[compound_ids.index(compound.id)]
    end

    def data_entries
      unless @data_entries
        t = Time.now
        @data_entries = Marshal.load($gridfs.find_one(_id: data_entries_id).data)
        bad_request_error "Data entries (#{data_entries_id}) are not a 2D-Array" unless @data_entries.is_a? Array and @data_entries.first.is_a? Array
        bad_request_error "Data entries (#{data_entries_id}) have #{@data_entries.size} rows, but dataset (#{id}) has #{compound_ids.size} compounds" unless @data_entries.size == compound_ids.size
        bad_request_error "Data entries (#{data_entries_id}) have #{@data_entries..first.size} columns, but dataset (#{id}) has #{feature_ids.size} features" unless @data_entries.first.size == feature_ids.size
        $logger.debug "Retrieving data: #{Time.now-t}"
      end
      @data_entries
    end

    # Find data entry values for a given compound and feature
    # @param compound [OpenTox::Compound] OpenTox Compound object
    # @param feature [OpenTox::Feature] OpenTox Feature object
    # @return [Array] Data entry values
    def values(compound, feature)
      #data_entries.where(:compound_id => compound.id, :feature_id => feature.id).distinct(:value)
      rows = (0 ... compound_ids.length).select { |r| compound_ids[r] == compound.id }
      col = feature_ids.index feature.id
      rows.collect{|row| data_entries[row][col]}
    end

    # Writers

    def compounds=(compounds)
      self.compound_ids = compounds.collect{|c| c.id}
    end

    def add_compound compound
        self.compound_ids << compound.id
    end

    def features=(features)
      self.feature_ids = features.collect{|f| f.id}
    end

    def add_feature feature
      self.feature_ids << feature.id
    end

    def self.create compounds, features, warnings=[], source=nil
      dataset = Dataset.new(:warnings => warnings)
      dataset.compounds = compounds
      dataset.features = features
      dataset
    end

    # for prediction result datasets
    # assumes that there are feature_ids with title prediction and confidence
    # @return [Array] of Hashes with keys { :compound, :value ,:confidence } (compound value is object not uri)
    # TODO
    #def predictions
    #end

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
    # TODO
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
    # TODO
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
    # TODO
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

    # Adding data methods
    # (Alternatively, you can directly change @data["feature_ids"] and @data["compounds"])

    # Create a dataset from file (csv,sdf,...)
    # @param filename [String]
    # @return [String] dataset uri
    # TODO
    #def self.from_sdf_file
    #end

    def self.from_csv_file file, source=nil, bioassay=true
      source ||= file
      table = CSV.read file, :skip_blanks => true
      dataset = Dataset.new(:source => source, :name => File.basename(file))
      dataset.parse_table table, bioassay
      dataset
    end

    # parse data in tabular format (e.g. from csv)
    # does a lot of guesswork in order to determine feature types
    def parse_table table, bioassay=true

      time = Time.now

      # features
      feature_names = table.shift.collect{|f| f.strip}
      warnings << "Duplicate features in table header." unless feature_names.size == feature_names.uniq.size
      compound_format = feature_names.shift.strip
      bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: SMILES, InChI." unless compound_format =~ /SMILES|InChI/i

      numeric = []
      # guess feature types
      feature_names.each_with_index do |f,i|
        metadata = {}
        values = table.collect{|row| val=row[i+1].to_s.strip; val.blank? ? nil : val }.uniq.compact
        types = values.collect{|v| v.numeric? ? true : false}.uniq
        if values.size == 0 # empty feature
        elsif  values.size > 5 and types.size == 1 and types.first == true # 5 max classes
          metadata["numeric"] = true
          numeric[i] = true
        else
          metadata["nominal"] = true
          metadata["accept_values"] = values
          numeric[i] = false
        end
        if bioassay
          if metadata["numeric"]
            feature = NumericBioAssay.find_or_create_by(metadata)
          elsif metadata["nominal"]
            feature = NominalBioAssay.find_or_create_by(metadata)
          end
        else
          metadata.merge({:measured => false, :calculated => true})
          if metadata["numeric"]
            feature = NumericFeature.find_or_create_by(metadata)
          elsif metadata["nominal"]
            feature = NominalFeature.find_or_create_by(metadata)
          end
        end
        feature_ids << OpenTox::Feature.find_or_create_by(metadata).id
      end
      #feature_ids = dataset.features.collect{|f| f.id.to_s}
      
      $logger.debug "Feature values: #{Time.now-time}"
      time = Time.now

      r = -1
      compound_time = 0
      value_time = 0

      # compounds and values
      @data_entries = Array.new(table.size){Array.new(table.first.size-1)}

      table.each_with_index do |vals,i|
        ct = Time.now
        identifier = vals.shift
        begin
          case compound_format
          when /SMILES/i
            compound = OpenTox::Compound.from_smiles(identifier)
            if compound.inchi.empty?
              warnings << "Cannot parse #{compound_format} compound '#{compound.strip}' at position #{i+2}, all entries are ignored."
              next
            end
          when /InChI/i
      # compounds and values
            compound = OpenTox::Compound.from_inchi(identifier)
          end
        rescue
          warnings << "Cannot parse #{compound_format} compound '#{compound}' at position #{i+2}, all entries are ignored."
          next
        end
        compound_time += Time.now-ct
        compound_ids << compound.id
          
        r += 1
        unless vals.size == feature_ids.size # way cheaper than accessing features
          warnings << "Number of values at position #{i+2} is different than header size (#{vals.size} vs. #{features.size}), all entries are ignored."
          next
        end

        cid = compound.id.to_s
        vals.each_with_index do |v,j|
          if v.blank?
            warnings << "Empty value for compound '#{identifier}' (row #{r+2}) and feature '#{feature_names[j]}' (column #{j+2})."
            next
          elsif numeric[j]
            @data_entries[i][j] = v.to_f
            #dataset.bulk << [cid,feature_ids[j],v.to_f]
          else
            @data_entries[i][j] = v.strip
            #dataset.bulk << [cid,feature_ids[j],v.strip]
          end
        end
      end
      compounds.duplicates.each do |compound|
        positions = []
        compounds.each_with_index{|c,i| positions << i+1 if !c.blank? and c.inchi == compound.inchi}
        warnings << "Duplicate compound #{compound.inchi} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
      end
      
      $logger.debug "Value parsing: #{Time.now-time} (Compound creation: #{compound_time})"
      time = Time.now
      #dataset.bulk_write
      save_all
      $logger.debug "Saving: #{Time.now-time}"

    end
  end
end
