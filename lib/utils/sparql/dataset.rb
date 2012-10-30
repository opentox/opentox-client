=begin
* Name: dataset.rb
* Description: Dataset SPARQL tools
* Author: Andreas Maunz <andreas@maunz.de>
* Date: 10/2012
=end

module OpenTox
  class Dataset

    # Load features via SPARQL (fast)
    # @param [String] uri Dataset URI
    # @return [Array] features OpenTox::Features in order
    def self.find_features_sparql(uri)
      sparql = "SELECT DISTINCT ?s FROM <#{uri}> WHERE {
        ?s <#{RDF.type}> <#{RDF::OT.Feature}> ;
           <#{RDF::OLO.index}> ?fidx
        } ORDER BY ?fidx"
      OpenTox::Backend::FourStore.query(sparql, "text/uri-list").split("\n").collect { |uri| OpenTox::Feature.new uri.strip }
    end

    # Load properties via SPARQL (fast)
    # @param [Array] uris URIs (assumed ordered)
    # @param [Hash] properties Properties (keys: user-defined identifier, values: rdf identifier as strings)
    # @return [Array] types Properties in order of URIs
    def self.find_props_sparql(uris, props)
      selects = props.keys
      conditions = selects.collect{ |k|
        "<#{props[k]}> ?#{k.to_s}"
      }
      h={}
      uris.each{ |uri|
        sparql = "SELECT ?id #{selects.collect{|k| "?#{k.to_s}"}.join(" ")} FROM <#{uri}> WHERE { ?id #{conditions.join(";")} }"
        res = OpenTox::Backend::FourStore.query(sparql, "text/uri-list")
        res.split("\n").inject(h){ |h,row| 
          values = row.split("\t")
          id=values.shift
          h[id] = {}
          values.each_with_index { |val,idx|
            h[id][selects[idx]] = [] unless h[id][selects[idx]]
            h[id][selects[idx]] << val.to_s
          }
          h
        }
      }
      h
    end

    # Load compounds via SPARQL (fast)
    # @param [String] uri Dataset URI
    # @return [Array] compounds Compounds in order
    def self.find_compounds_sparql(uri)
      sparql = "SELECT DISTINCT ?compound FROM <#{uri}> WHERE {
        ?s <#{RDF.type}> <#{RDF::OT.DataEntry}> ;
           <#{RDF::OLO.index}> ?cidx;
           <#{RDF::OT.compound}> ?compound
        } ORDER BY ?cidx"
      OpenTox::Backend::FourStore.query(sparql, "text/uri-list").split("\n").collect { |uri| OpenTox::Compound.new uri.strip }
    end

    # Load data entries via SPARQL (fast)
    # @param [String] uri Dataset uri
    # @return [Array] entries Data entries, ordered primarily over cols and secondarily over rows
    def self.find_data_entries_sparql(uri)
      sparql = "SELECT ?value FROM <#{uri}> WHERE {
        ?data_entry <#{RDF::OLO.index}> ?cidx ;
                    <#{RDF::OT.values}> ?v .
        ?v          <#{RDF::OT.feature}> ?f;
                    <#{RDF::OT.value}> ?value .
        ?f          <#{RDF::OLO.index}> ?fidx.
        } ORDER BY ?fidx ?cidx"
      OpenTox::Backend::FourStore.query(sparql,"text/uri-list").split("\n").collect { |val| val.strip }
    end

  end
end
