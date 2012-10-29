=begin
* Name: dataset.rb
* Description: Dataset RDF tools
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Dataset

    # Load features via RDF (slow)
    # @param [String] uri Dataset URI
    # @return [Array] features Features in order
    def self.find_features_rdf(rdf)
      query = RDF::Query.new do
        pattern [:uri, RDF.type, RDF::OT.Feature]
        pattern [:uri, RDF::OLO.index, :idx]
      end
      query.execute(rdf).sort_by{|s| s.idx}.collect{|s| OpenTox::Feature.new(s.uri.to_s)}
    end

    # Load compounds via RDF (slow)
    # @param [String] uri Dataset URI
    # @return [Array] compounds Compounds in order
    def self.find_compounds_rdf(rdf)
      query = RDF::Query.new do
        pattern [:uri, RDF.type, RDF::OT.Compound]
        pattern [:uri, RDF::OLO.index, :idx]
      end
      query.execute(rdf).sort_by{|s| s.idx}.collect{|s| OpenTox::Compound.new(s.uri.to_s)}
    end

    # Load data entries via RDF (slow)
    # @param [String] uri Dataset uri
    # @return [Array] entries Data entries, ordered primarily over rows and secondarily over cols
    def self.find_data_entries_rdf(rdf)
      query = RDF::Query.new do
        pattern [:data_entry, RDF::OLO.index, :cidx] # compound index: now a free variable
        pattern [:data_entry, RDF::OT.values, :vals]
        pattern [:vals, RDF::OT.feature, :f]
        pattern [:f, RDF::OLO.index, :fidx]
        pattern [:vals, RDF::OT.value, :val]
      end
      query.execute(rdf).order_by(:fidx, :cidx).collect { |s| s.val.to_s }
    end

  end
end
