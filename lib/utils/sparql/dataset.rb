=begin
* Name: dataset.rb
* Description: Dataset SPARQL tools
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Dataset

    # Load features via SPARQL (fast)
    # @param [String] Dataset URI
    # @return [Array] Features in order
    def self.find_features_sparql(uri)
      sparql = "SELECT DISTINCT ?s FROM <#{uri}> WHERE {
        ?s <#{RDF.type}> <#{RDF::OT.Feature}> ;
           <#{RDF::OLO.index}> ?fidx
        } ORDER BY ?fidx"
      OpenTox::Backend::FourStore.query(sparql, "text/uri-list").split("\n").collect { |uri| OpenTox::Feature.new uri.strip }
    end

    # Load compounds via SPARQL (fast)
    # @param [String] Dataset URI
    # @return [Array] Compounds in order
    def self.find_compounds_sparql(uri)
      sparql = "SELECT DISTINCT ?compound FROM <#{uri}> WHERE {
        ?s <#{RDF.type}> <#{RDF::OT.DataEntry}> ;
           <#{RDF::OLO.index}> ?cidx;
           <#{RDF::OT.compound}> ?compound
        } ORDER BY ?cidx"
      OpenTox::Backend::FourStore.query(sparql, "text/uri-list").split("\n").collect { |uri| OpenTox::Compound.new uri.strip }
    end

    # Load data entries via SPARQL (fast)
    # @param [String] Dataset uri
    # @return [Array] Data entries, ordered primarily over rows and secondarily over cols
    def self.find_data_entries_sparql(uri)
      sparql = "SELECT ?value FROM <#{uri}> WHERE {
        ?data_entry <#{RDF::OLO.index}> ?cidx ;
                    <#{RDF::OT.values}> ?v .
        ?v          <#{RDF::OT.feature}> ?f;
                    <#{RDF::OT.value}> ?value .
        ?f          <#{RDF::OLO.index}> ?fidx.
        } ORDER BY ?cidx ?fidx"
      OpenTox::Backend::FourStore.query(sparql,"text/uri-list").split("\n").collect { |val| val.strip }
    end

  end
end
