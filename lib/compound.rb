CACTUS_URI="http://cactus.nci.nih.gov/chemical/structure/"
require 'openbabel'

module OpenTox

  # Ruby wrapper for OpenTox Compound Webservices (http://opentox.org/dev/apis/api-1.2/structure).
  class Compound

    attr_reader :inchi

    def initialize inchi
      @inchi = inchi
    end

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles smiles
      OpenTox::Compound.new obconversion(smiles,"smi","inchi")
    end

    # Create a compound from inchi string
    # @param inchi [String] smiles InChI string
    # @return [OpenTox::Compound] Compound
    def self.from_inchi inchi
      OpenTox::Compound.new inchi
    end

    # Create a compound from sdf string
    # @param sdf [String] smiles SDF string
    # @return [OpenTox::Compound] Compound
    def self.from_sdf sdf
      OpenTox::Compound.new obconversion(sdf,"sdf","inchi")
    end

    # Create a compound from name. Relies on an external service for name lookups.
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    # @param name [String] can be also an InChI/InChiKey, CAS number, etc
    # @return [OpenTox::Compound] Compound
    def self.from_name name
      OpenTox::Compound.new RestClientWrapper.get File.join(CACTUS_URI,URI.escape(name),"stdinchi")
    end

    # Get InChIKey
    # @return [String] InChI string
    def inchikey
      obconversion(@inchi,"inchi","inchikey")
    end

    # Get (canonical) smiles
    # @return [String] Smiles string
    def smiles
      obconversion(@inchi,"inchi","smi") # "can" gives nonn-canonical smiles??
    end

    # Get sdf
    # @return [String] SDF string
    def sdf
      obconversion(@inchi,"inchi","sdf")
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
      obconversion(@inchi,"inchi","_png2")
    end

=begin
    # Get URI of compound image
    # @return [String] Compound image URI
    def image_uri
      File.join @data["uri"], "image"
    end
=end

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

    private

    def self.obconversion(identifier,input_format,output_format,option=nil)
      obconversion = OpenBabel::OBConversion.new
      obconversion.set_options(option, OpenBabel::OBConversion::OUTOPTIONS) if option
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_and_out_formats input_format, output_format
      obconversion.read_string obmol, identifier
      case output_format
      when /smi|can|inchi/
        obconversion.write_string(obmol).gsub(/\s/,'').chomp
      else
        obconversion.write_string(obmol)
      end
    end

    def obconversion(identifier,input_format,output_format,option=nil)
      self.class.obconversion(identifier,input_format,output_format,option=nil)
    end
  end
end
