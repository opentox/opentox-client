=begin
* Name: dataset.rb
* Description: Dataset shims
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox

  # Shims for the Dataset Class
  class Dataset

    attr_accessor :feature_positions, :compound_positions

    # Load a dataset from URI
    # @param [String] Dataset URI
    # @return [OpenTox::Dataset] Dataset object
    def self.find(uri, subjectid=nil)
      return nil unless uri
      ds = OpenTox::Dataset.new uri, subjectid
      ds.get
      ds
    end
    
    def self.exist?(uri, subjectid=nil)
      ds = OpenTox::Dataset.new uri, subjectid
      begin
        ds.get_metadata
        true
      rescue
        false
      end
    end
    
    def split( compound_indices, feats, metadata, subjectid=nil)
      
      raise "Dataset.split : pls give compounds as indices" if compound_indices.size==0 or !compound_indices[0].is_a?(Fixnum)
      raise "Dataset.split : pls give features as feature objects (given: #{feats})" if feats!=nil and feats.size>0 and !feats[0].is_a?(OpenTox::Feature)
      $logger.debug "split dataset using "+compound_indices.size.to_s+"/"+@compounds.size.to_s+" compounds"
      
      dataset = OpenTox::Dataset.new(nil, subjectid)
      dataset.metadata = metadata
      dataset.features = (feats ? feats : self.features)
      compound_indices.each do |c_idx|
        dataset << [ self.compounds[c_idx] ] + dataset.features.each_with_index.collect{|f,f_idx| self.data_entries[c_idx][f_idx]} 
      end

      #compound_indices.each do |c_idx|
        # c = @compounds[c_idx]
        # dataset.add_compound(c)
        # if @data_entries[c]
          # features.each do |f|
            # if @data_entries[c][f] 
              # dataset.add_data_entry c,f,@data_entries[c][f][entry_index(c_idx)]
            # else
              # dataset.add_data_entry c,f,nil
            # end
          # end
        # end
      # end
      
      dataset.put subjectid
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
      build_feature_positions unless @feature_positions
      @data_entries[compound_index][@feature_positions[feature_uri]]
    end

    ### Index Structures

    # Create value map
    # @param [OpenTox::Feature] A feature
    # @return [Hash] A hash with keys 1...feature.training_classes.size and values training classes
    def value_map(feature)
      training_classes = feature.accept_values
      raise "no accept values for feature #{feature.uri} in dataset #{uri}" unless training_classes
      training_classes.each_index.inject({}) { |h,idx| h[idx+1]=training_classes[idx]; h } 
    end

    # Create feature positions map
    # @return [Hash] A hash with keys feature uris and values feature positions
    def build_feature_positions
      unless @feature_positions
        @feature_positions = @features.each_index.inject({}) { |h,idx| 
          internal_server_error "Duplicate Feature '#{@features[idx].uri}' in dataset '#{@uri}'" if h[@features[idx].uri]
          h[@features[idx].uri] = idx 
          h
        }
      end
    end

    # Create compounds positions map
    # @return [Hash] A hash with keys compound uris and values compound position arrays
    def build_compound_positions
      unless @compound_positions
        @compound_positions = @compounds.each_index.inject({}) { |h,idx| 
          inchi=OpenTox::Compound.new(@compounds[idx].uri).inchi
          h[inchi] = [] unless h[inchi]
          h[inchi] << idx if inchi =~ /InChI/
          h
        }
      end
    end


    ### Associative Search Operations

    # Search a dataset for a feature given its URI
    # @param [String] Feature URI
    # @return [OpenTox::Feature] Feature object, or nil if not present
    def find_feature(uri)
      build_feature_positions
      res = @features[@feature_positions[uri]] if @feature_positions[uri]
      res
    end

    # Search a dataset for a compound given its URI
    # @param [String] Compound URI
    # @return [OpenTox::Compound] Array of compound objects, or nil if not present
    def find_compound(uri)
      build_compound_positions
      inchi = OpenTox::Compound.new(uri).inchi
      res = @compounds[@compound_positions[inchi]] if inchi =~ /InChI/ and @compound_positions[inchi]
      res
    end

    # Search a dataset for a data entry given compound URI and feature URI
    # @param [String] Compound URI
    # @param [String] Feature URI
    # @return [Object] Data entry, or nil if not present
    def find_data_entry(compound_uri, feature_uri)
      build_compound_positions
      build_feature_positions
      inchi = OpenTox::Compound.new(compound_uri).inchi
      if @compound_positions[inchi] && @feature_positions[feature_uri]
        res = []
        @compound_positions[inchi].each { |idx|
          res << data_entries[idx][@feature_positions[feature_uri]]
        }
      end
      res
    end

  end


end
