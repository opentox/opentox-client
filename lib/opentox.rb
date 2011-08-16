module OpenTox

  attr_reader :uri
  attr_accessor :metadata

  # Initialize OpenTox object with optional uri
  # @param [optional, String] URI
  def initialize(uri=nil,subjectid=nil)
    @metadata = {}
    @subjectid = subjectid
    self.uri = uri if uri
  end

  # Set URI
  # @param [String] URI
  def uri=(uri)
    @uri = uri
    @metadata[XSD.anyURI] = uri
  end

  # Get all objects from a service
  # @return [Array] List of available URIs
  def self.all(uri, subjectid=nil)
    RestClientWrapper.get(uri,:accept => "text/uri-list", :subjectid => subjectid).to_s.split(/\n/)
  end

  # Load (and return) metadata from object URI
  # @return [Hash] Metadata
  def load_metadata
    @metadata = Parser::Owl::Generic.new(@uri).load_metadata
    @metadata
  end

  # Add/modify metadata, existing entries will be overwritten
  # @example
  #   dataset.add_metadata({DC.title => "any_title", DC.creator => "my_email"})
  # @param [Hash] metadata Hash mapping predicate_uris to values
  def add_metadata(metadata)
    metadata.each do |k,v|
      if v.is_a? Array
        @metadata[k] = [] unless @metadata[k]
        @metadata[k] << v
      else
        @metadata[k] = v 
      end
    end
  end

  # Get OWL-DL representation in RDF/XML format
  # @return [application/rdf+xml] RDF/XML representation
  def to_rdfxml
    s = Serializer::Owl.new
    s.add_metadata(@uri,@metadata)
    s.to_rdfxml
  end

  # deletes the resource, deletion should have worked when no RestCallError raised
  def delete
    RestClientWrapper.delete(uri,:subjectid => @subjectid)
  end

end

