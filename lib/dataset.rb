module OpenTox

  # Ruby wrapper for OpenTox Dataset Webservices (http://opentox.org/dev/apis/api-1.2/dataset).
  class Dataset 

    def data_entries
      data_entries = []
      #pull 
      #@reload = false
      begin
        self.[](RDF::OT.dataEntry).collect{|data_entry| data_entries << @rdf.to_hash[data_entry] }
      rescue
      end
      begin
      # TODO: remove API 1.1
        self.[](RDF::OT1.dataEntry).collect{|data_entry| data_entries << @rdf.to_hash[data_entry] }
      rescue
      end
      #@reload = true
      data_entries
    end

    def compounds
      uri = File.join(@uri,"compounds")
      RestClientWrapper.get(uri,{},{:accept => "text/uri-list", :subjectid => @subjectid}).split("\n").collect{|uri| OpenTox::Compound.new uri}
    end

    def features
      uri = File.join(@uri,"features")
      RestClientWrapper.get(uri,{},{:accept => "text/uri-list", :subjectid => @subjectid}).split("\n").collect{|uri| OpenTox::Feature.new uri}
    end

  end
end
