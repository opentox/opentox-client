#require "openbabel"
CACTUS_URI="http://cactus.nci.nih.gov/chemical/structure/"

module OpenTox

  # Ruby wrapper for OpenTox Compound Webservices (http://opentox.org/dev/apis/api-1.2/structure).
  class Compound

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles smiles, subjectid=nil
      Compound.new RestClientWrapper.post(service_uri, smiles, {:content_type => 'chemical/x-daylight-smiles', :subjectid => subjectid})
    end

    # Create a compound from inchi string
    # @param inchi [String] smiles InChI string
    # @return [OpenTox::Compound] Compound
    def self.from_inchi inchi, subjectid=nil
      Compound.new RestClientWrapper.post(service_uri, inchi, {:content_type => 'chemical/x-inchi', :subjectid => subjectid})
    end

    # Create a compound from sdf string
    # @param sdf [String] smiles SDF string
    # @return [OpenTox::Compound] Compound
    def self.from_sdf sdf, subjectid=nil
      Compound.new RestClientWrapper.post(service_uri, sdf, {:content_type => 'chemical/x-mdl-sdfile', :subjectid => subjectid})
    end

    # Create a compound from name. Relies on an external service for name lookups.
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    # @param name [String] can be also an InChI/InChiKey, CAS number, etc
    # @return [OpenTox::Compound] Compound
    def self.from_name name, subjectid=nil
      @inchi = RestClientWrapper.get File.join(CACTUS_URI,URI.escape(name),"stdinchi")
      Compound.new RestClientWrapper.post(service_uri, @inchi, {:content_type => 'chemical/x-inchi', :subjectid => subjectid})
    end

    # Get InChI
    # @return [String] InChI string
    def inchi
      @inchi ||= RestClientWrapper.get(@uri,{},{:accept => 'chemical/x-inchi'}).chomp
    end

    # Get InChIKey
    # @return [String] InChI string
    def inchikey
      @inchikey ||= RestClientWrapper.get(@uri,{},{:accept => 'chemical/x-inchikey'}).chomp
    end

    # Get (canonical) smiles
    # @return [String] Smiles string
    def smiles
      @smiles ||= RestClientWrapper.get(@uri,{},{:accept => 'chemical/x-daylight-smiles'}).chomp
    end

    # Get sdf
    # @return [String] SDF string
    def sdf
      RestClientWrapper.get(@uri,{},{:accept => 'chemical/x-mdl-sdfile'}).chomp
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
      RestClientWrapper.get(File.join @uri, "image")
    end

    # Get URI of compound image
    # @return [String] Compound image URI
    def image_uri
      File.join @uri, "image"
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
      raise_internal_error "not yet implemented"
    end

    # @return [String] ChEMBL database compound id, derieved via restcall to chembl
    def chemblid
      # https://www.ebi.ac.uk/chembldb/ws#individualCompoundByInChiKey
      uri = "http://www.ebi.ac.uk/chemblws/compounds/smiles/#{smiles}.json"
      @chemblid = JSON.parse(RestClientWrapper.get(uri))["compounds"].first["chemblId"]
    end

=begin
    # Match a smarts string
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    #   compound.match?("cN") # returns false
    # @param [String] smarts Smarts string
    def match?(smarts)
      matcher = Algorithm.new File.join($algorithm[:uri],"descriptor","smarts")
      matcher.run :compound_uri => @uri, :smarts => smarts, :count => false
    end

    # Match an array of smarts strings, returns array with matching smarts
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    #   compound.match(['cc','cN']) # returns ['cc']
    # @param [Array] smarts_array Array with Smarts strings
    # @return [Array] Array with matching Smarts strings
    def match(smarts_array)
      matcher = Algorithm.new File.join($algorithm[:uri],"descriptor","smarts")
      matcher.run :compound_uri => @uri, :smarts => smarts_array, :count => false
    end

    # Match a smarts string
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    #   compound.match?("cN") # returns false
    # @param [String] smarts Smarts string
    def match?(smarts)
      obconversion = OpenBabel::OBConversion.new
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_format('inchi')
      obconversion.read_string(obmol,@inchi)
      smarts_pattern = OpenBabel::OBSmartsPattern.new
      smarts_pattern.init(smarts)
      smarts_pattern.match(obmol)
    end

    # Match an array of smarts strings, returns array with matching smarts
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    #   compound.match(['cc','cN']) # returns ['cc']
    # @param [Array] smarts_array Array with Smarts strings
    # @return [Array] Array with matching Smarts strings
    def match(smarts_array)
      # avoid recreation of OpenBabel objects
      obconversion = OpenBabel::OBConversion.new
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_format('inchi')
      obconversion.read_string(obmol,@inchi)
      smarts_pattern = OpenBabel::OBSmartsPattern.new
      smarts_array.collect do |smarts|
        smarts_pattern.init(smarts)
        smarts if smarts_pattern.match(obmol)
      end.compact
      #smarts_array.collect { |s| s if match?(s)}.compact
    end

    # Get URI of compound image with highlighted fragments
    #
    # @param [Array] activating Array with activating Smarts strings
    # @param [Array] deactivating Array with deactivating Smarts strings
    # @return [String] URI for compound image with highlighted fragments
    def matching_smarts_image_uri(activating, deactivating)
      activating_smarts = URI.encode "\"#{activating.join("\"/\"")}\""
      deactivating_smarts = URI.encode "\"#{deactivating.join("\"/\"")}\""
      File.join @uri, "smarts/activating", URI.encode(activating_smarts),"deactivating", URI.encode(deactivating_smarts)
    end


    private

    # Convert sdf to inchi
    def self.sdf2inchi(sdf)
      Compound.obconversion(sdf,'sdf','inchi')
    end

    # Convert smiles to inchi
    def self.smiles2inchi(smiles)
      Compound.obconversion(smiles,'smi','inchi')
    end

    # Convert smiles to canonical smiles
    def self.smiles2cansmi(smiles)
      Compound.obconversion(smiles,'smi','can')
    end

    # Convert identifier from OpenBabel input_format to OpenBabel output_format
		def self.obconversion(identifier,input_format,output_format)
			obconversion = OpenBabel::OBConversion.new
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



    # Match an array of smarts strings, returns hash
    # Keys: matching smarts, values: number of non-unique hits, or 1
    # @param [Array] smarts_array Array with Smarts strings
    # @param use_hits [Boolean] Whether non-unique hits or 1 should be produced
    # @return [Hash] Hash with matching Smarts as keys, nr-of-hits/1 as values
    # @example
    #   compound = Compound.from_name("Benzene")
    #   compound.match(['cc','cN'],true) # returns { 'cc' => 12 }, 'cN' is not included because it does not match
    #   compound.match(['cc','cN'],false) # returns { 'cc' => 1 }
    def match_hits(smarts_array, use_hits=true)
      obconversion = OpenBabel::OBConversion.new
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_format('inchi')
      obconversion.read_string(obmol,inchi)
      smarts_pattern = OpenBabel::OBSmartsPattern.new
      smarts_hits = {}
      smarts_array.collect do |smarts|
        smarts_pattern.init(smarts)
        if smarts_pattern.match(obmol)
          if use_hits
            hits = smarts_pattern.get_map_list
            smarts_hits[smarts] = hits.to_a.size
          else
            smarts_hits[smarts] = 1
          end
        end
      end
      smarts_hits
    end

    # Provided for backward compatibility
    def match(smarts_array)
      match_hits(smarts_array,false)
    end
=end

  end
end
