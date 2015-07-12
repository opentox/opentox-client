CACTUS_URI="http://cactus.nci.nih.gov/chemical/structure/"

module OpenTox

  # Ruby wrapper for OpenTox Compound Webservices (http://opentox.org/dev/apis/api-1.2/structure).
  class Compound

    def initialize uri
      @data = {}
      @data["uri"] = uri
    end

    def ==(c)
      @data["uri"] == c.uri
    end

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles smiles
      Compound.new RestClientWrapper.post(service_uri, smiles, {:content_type => 'chemical/x-daylight-smiles'})
    end

    # Create a compound from inchi string
    # @param inchi [String] smiles InChI string
    # @return [OpenTox::Compound] Compound
    def self.from_inchi inchi
      Compound.new RestClientWrapper.post(service_uri, inchi, {:content_type => 'chemical/x-inchi'})
    end

    # Create a compound from sdf string
    # @param sdf [String] smiles SDF string
    # @return [OpenTox::Compound] Compound
    def self.from_sdf sdf
      Compound.new RestClientWrapper.post(service_uri, sdf, {:content_type => 'chemical/x-mdl-sdfile'})
    end

    # Create a compound from name. Relies on an external service for name lookups.
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    # @param name [String] can be also an InChI/InChiKey, CAS number, etc
    # @return [OpenTox::Compound] Compound
    def self.from_name name
      @inchi = RestClientWrapper.get File.join(CACTUS_URI,URI.escape(name),"stdinchi")
      Compound.new RestClientWrapper.post(service_uri, @inchi, {:content_type => 'chemical/x-inchi'})
    end

    # Get InChI
    # @return [String] InChI string
    def inchi
      @inchi ||= RestClientWrapper.get(@data["uri"],{},{:accept => 'chemical/x-inchi'}).chomp
    end

    # Get InChIKey
    # @return [String] InChI string
    def inchikey
      @inchikey ||= RestClientWrapper.get(@data["uri"],{},{:accept => 'chemical/x-inchikey'}).chomp
    end

    # Get (canonical) smiles
    # @return [String] Smiles string
    def smiles
      @smiles ||= RestClientWrapper.get(@data["uri"],{},{:accept => 'chemical/x-daylight-smiles'}).chomp
    end

    # Get sdf
    # @return [String] SDF string
    def sdf
      RestClientWrapper.get(@data["uri"],{},{:accept => 'chemical/x-mdl-sdfile'}).chomp
    end

    # Get gif image
    # @return [image/gif] Image data
    def gif
      RestClientWrapper.get File.join(CACTUS_URI,inchi,"image")
    end

    # Get png image
    # @example
    #   image = compound.png
    # @return [image/png] Image data
    def png
      RestClientWrapper.get(File.join @data["uri"], "image")
    end

    # Get URI of compound image
    # @return [String] Compound image URI
    def image_uri
      File.join @data["uri"], "image"
    end

    # Get all known compound names. Relies on an external service for name lookups.
    # @example
    #   names = compound.names
    # @return [String] Compound names
    def names
      RestClientWrapper.get("#{CACTUS_URI}#{inchi}/names").split("\n")
    end

    # @return [String] PubChem Compound Identifier (CID), derieved via restcall to pubchem
    def cid
      pug_uri = "http://pubchem.ncbi.nlm.nih.gov/rest/pug/"
      @cid ||= RestClientWrapper.post(File.join(pug_uri, "compound", "inchi", "cids", "TXT"),{:inchi => inchi}).strip
    end

    # @todo
    def chebi
      internal_server_error "not yet implemented"
    end

    # @return [String] ChEMBL database compound id, derieved via restcall to chembl
    def chemblid
      # https://www.ebi.ac.uk/chembldb/ws#individualCompoundByInChiKey
      uri = "http://www.ebi.ac.uk/chemblws/compounds/smiles/#{smiles}.json"
      @chemblid = JSON.parse(RestClientWrapper.get(uri))["compounds"].first["chemblId"]
    end
  end
end
