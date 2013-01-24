module OpenTox
  AA = $aa[:uri] if defined? $aa
  AA ||= "https://opensso.in-silico.ch" #if not set in .opentox/conf/[application]/[test].rb
  #Module for Authorization and Authentication
  #@example Authentication
  #  require "opentox-client"
  #  OpenTox::Authorization::AA = "https://opensso.in-silico.ch" #if not set in .opentox/conf/[environment].yaml
  #  subjectid = OpenTox::Authorization.authenticate("username", "password")
  #@see http://www.opentox.org/dev/apis/api-1.2/AA OpenTox A&A API 1.2 specification

  module Authorization

    #Helper Class to create and send default policies out of xml templates
    #@example Creating a default policy to a URI
    #  aa=OpenTox::Authorization::AA.new(tok)
    #  xml=aa.get_xml('http://uri....')
    #  OpenTox::Authorization.create_policy(xml,tok)

    class Helper
      attr_accessor :user, :subjectid, :policy

      #Generates AA object - requires subjectid
      # @param [String] subjectid
      def initialize(subjectid)
        @user = Authorization.get_user(subjectid)
        @subjectid = subjectid
        @policy = Policies.new()
      end

      #Cleans AA Policies and loads default xml file into policy attribute
      #set uri and user, returns Policyfile(XML) for open-sso
      # @param [String] URI to create a policy for
      def get_xml(uri)
        @policy.drop_policies
        @policy.load_default_policy(@user, uri)
        return @policy.to_xml
      end

      #Loads and sends Policyfile(XML) to open-sso server
      # @param [String] URI to create a policy for
      def send(uri)
        xml = get_xml(uri)
        ret = false
        ret = Authorization.create_policy(xml, @subjectid)
        $logger.warn "Create policy on openSSO failed for URI: #{uri} subjectid: #{@subjectid}. Will try again." if !ret
        ret = Authorization.create_policy(xml, @subjectid) if !ret
        $logger.debug "Policy send with subjectid: #{@subjectid}"
        $logger.error "Not created Policy is: #{xml}" if !ret
        ret
      end
    end

    #Returns the open-sso server set in the config file .opentox/config/[environment].yaml
    # @return [String, nil] the openSSO server URI or nil
    def self.server
      return AA
    end

    #Authentication against OpenSSO. Returns token. Requires Username and Password.
    # @param [String, String]Username,Password
    # @return [String, nil] gives subjectid or nil
    def self.authenticate(user, pw)
      return nil if !AA
      begin
        out = RestClientWrapper.post("#{AA}/auth/authenticate",{:username=>user, :password => pw}).sub("token.id=","").sub("\n","")
        return out
      rescue
        resource_not_found_error "#{out.inspect}"
        return nil
      end
    end

    #Logout on opensso. Make token invalid. Requires token
    # @param [String]subjectid the subjectid
    # @return [Boolean] true if logout is OK
    def self.logout(subjectid)
      begin
        out = RestClientWrapper.post("#{AA}/auth/logout",:subjectid => subjectid)
        return true unless is_token_valid(subjectid)
      rescue #openSSO throws 500 if token is invalid
        return false
      end
      return false
    end

    #Authorization against OpenSSO for a URI with request-method (action) [GET/POST/PUT/DELETE]
    # @param [String,String,String]uri,action,subjectid
    # @return [Boolean, nil]  returns true, false or nil (if authorization-request fails).
    def self.authorize(uri, action, subjectid)
      return true if !AA
      return true if RestClientWrapper.post("#{AA}/auth/authorize",{:uri => uri, :action => action, :subjectid => subjectid})== "boolean=true\n"
      return false
    end

    #Checks if a token is a valid token
    # @param [String]subjectid subjectid from openSSO session
    # @return [Boolean] subjectid is valid or not.
    def self.is_token_valid(subjectid)
      return true if !AA
      begin
        return true if RestClientWrapper.post("#{AA}/auth/isTokenValid",:tokenid => subjectid) == "boolean=true\n"
      rescue #do rescue because openSSO throws 401 if token invalid
        return false
      end
      return false
    end

    #Returns array with all policies of the token owner
    # @param [String]subjectid requires subjectid
    # @return [Array, nil] returns an Array of policy names or nil if request fails
    def self.list_policies(subjectid)
      #begin
        out = RestClientWrapper.get("#{AA}/pol",nil,:subjectid => subjectid)
        return out.split("\n")
      #rescue
      #  return nil
      #end
    end

    #Returns a policy in xml-format
    # @param [String, String]policy,subjectid
    # @return [String] XML of the policy
    def self.list_policy(policy, subjectid)
      #begin
        return RestClientWrapper.get("#{AA}/pol",nil,{:subjectid => subjectid,:id => policy})
      #rescue
      # return nil
      #end
    end

    # Lists policies alongside with affected uris
    # @param [String] subjectid
    # @return [Hash] keys: all policies of the subjectid owner, values: uris affected by those policies
    def self.list_policies_uris( subjectid )
      names = list_policies(subjectid)
      policies = {}
      names.each do |n|
        policies[n] = list_policy_uris( n, subjectid )
      end
      policies
    end

    # Lists policies alongside with affected uris
    # @param [String] subjectid
    # @return [Hash] keys: all policies of the subjectid owner, values: uris affected by those policies
    def self.list_policy_uris( policy, subjectid )
      p = OpenTox::Policies.new
      p.load_xml( list_policy(policy, subjectid) )
      p.uris
    end

    #Returns the owner (who created the first policy) of an URI
    # @param [String, String]uri,subjectid
    # return [String, nil]owner,nil returns owner of the URI
    def self.get_uri_owner(uri, subjectid)
      #begin
      return RestClientWrapper.get("#{AA}/pol",nil,{:subjectid => subjectid, :uri => uri}).sub("\n","")
      #rescue
      #  return nil
      #end
    end

    #Returns true or false if owner (who created the first policy) of an URI
    # @param [String, String]uri,subjectid
    # return [Boolean]true,false status of ownership of the URI
    def self.uri_owner?(uri, subjectid)
      get_uri_owner(uri, subjectid) == get_user(subjectid)
    end

    #Checks if a policy exists to a URI. Requires URI and token.
    # @param [String, String]uri,subjectid
    # return [Boolean]
    def self.uri_has_policy(uri, subjectid)
      owner = get_uri_owner(uri, subjectid)
      return true if owner and owner != "null"
      false
    end

    #List all policynames for a URI. Requires URI and token.
    # @param [String, String]uri,subjectid
    # return [Array, nil] returns an Array of policy names or nil if request fails
    def self.list_uri_policies(uri, subjectid)
      #begin
        out = RestClientWrapper.get("#{AA}/pol",nil,{:uri => uri, :polnames => true, :subjectid => subjectid})
        policies = []; notfirstline = false
        out.split("\n").each do |line|
          policies << line if notfirstline
          notfirstline = true
        end
        return policies
      #rescue
      #  return nil
      #end
    end

    #Sends a policy in xml-format to opensso server. Requires policy-xml and token.
    # @param [String, String]policyxml,subjectid
    # return [Boolean] returns true if policy is created
    def self.create_policy(policy, subjectid)
      #begin
        $logger.debug "OpenTox::Authorization.create_policy policy: #{policy[168,43]} with token:" + subjectid.to_s + " length: " + subjectid.length.to_s
        return true if RestClientWrapper.post("#{AA}/Pol/opensso-pol",policy, {:subjectid => subjectid, :content_type =>  "application/xml"})
      #rescue
        return false
      #end
    end

    #Deletes a policy
    # @param [String, String]policyname,subjectid
    # @return [Boolean,nil]
    def self.delete_policy(policy, subjectid)
      #begin
        $logger.debug "OpenTox::Authorization.delete_policy policy: #{policy} with token: #{subjectid}"
        return true if RestClientWrapper.delete("#{AA}/pol",nil, {:subjectid => subjectid, :id => policy})
      #rescue
        return nil
      #end
    end

    #Returns array of the LDAP-Groups of an user
    # @param [String]subjectid
    # @return [Array] gives array of LDAP groups of a user
    def self.list_user_groups(user, subjectid)
      #begin
        out = RestClientWrapper.post("#{AA}/opensso/identity/read", {:name => user, :admin => subjectid, :attributes_names => "group"})
        grps = []
        out.split("\n").each do |line|
          grps << line.sub("identitydetails.group=","") if line.include?("identitydetails.group=")
        end
        return grps
      #rescue
      #  []
      #end
    end

    #Returns the owner (user id) of a token
    # @param [String]subjectid
    # @return [String]user
    def self.get_user(subjectid)
      #begin
        out = RestClientWrapper.post("#{AA}/opensso/identity/attributes", {:subjectid => subjectid, :attributes_names => "uid"})
        user = ""; check = false
        out.split("\n").each do |line|
          if check
            user = line.sub("userdetails.attribute.value=","") if line.include?("userdetails.attribute.value=")
            check = false
          end
          check = true if line.include?("userdetails.attribute.name=uid")
        end
        return user
      #rescue
      #  nil
      #end
    end

    #Send default policy with Authorization::Helper class
    # @param [String, String]URI,subjectid
    def self.send_policy(uri, subjectid)
      return true if !AA
      aa  = Authorization::Helper.new(subjectid)
      ret = aa.send(uri)
      $logger.debug "OpenTox::Authorization send policy for URI: #{uri} | subjectid: #{subjectid} - policy created: #{ret}"
      ret
    end

    #Deletes all policies of an URI
    # @param [String, String]URI,subjectid
    # @return [Boolean]
    def self.delete_policies_from_uri(uri, subjectid)
      policies = list_uri_policies(uri, subjectid)
      if policies
        policies.each do |policy|
          ret = delete_policy(policy, subjectid)
          $logger.debug "OpenTox::Authorization delete policy: #{policy} - with result: #{ret}"
        end
      end
      return true
    end

    # Checks (if subjectid is valid) if a policy exist and create default policy if not
    # @param [String] uri
    # @param [String] subjectid
    # @return [Boolean] true if policy checked/created successfully (or no uri/subjectid given), false else
    def self.check_policy(uri, subjectid)
      return true unless uri and subjectid
      token_valid = OpenTox::Authorization.is_token_valid(subjectid)
      $logger.debug "OpenTox::Authorization.check_policy with uri: #{uri}, subjectid: #{subjectid} is valid: #{token_valid}"
      # check if subjectid is valid
      unless token_valid
        # abort if invalid
        $logger.error "OpenTox::Authorization.check_policy, subjectid NOT valid: #{subjectid}"
        return false
      end

      if !uri_has_policy(uri, subjectid)
        # if no policy exists, create a policy, return result of send policy
        send_policy(uri, subjectid)
      else
        # if policy exists check for POST rights
        if authorize(uri, "POST", subjectid)
          true
       else
          $logger.error "OpenTox::Authorization.check_policy, already exists, but no POST-authorization with subjectid: #{subjectid}"
          false
        end
      end
      true
    end

    class << self
      alias :token_valid? :is_token_valid
    end

    # Check Authorization for a resource (identified via URI) with method and subjectid.
    # @param [String] uri
    # @param [String] request_method, should be GET, POST, PUT, DELETE
    # @param [String] subjectid
    # @return [Boolean] true if access granted, else otherwise
    def self.authorized?(uri, request_method, subjectid)
      request_method = request_method.to_sym if request_method
      if $aa[:free_request].include?(request_method)
        #$logger.debug "authorized? >>true<< (request is free), method: #{request_method}, URI: #{uri}, subjectid: #{subjectid}"
        true
      elsif OpenTox::Authorization.free_uri?(uri, request_method)
        #$logger.debug "authorized? >>true<< (uris is free_uri), method: #{request_method}, URI: #{uri}, subjectid: #{subjectid}"
        true
      elsif $aa[:authenticate_request].include?(request_method)
        ret = OpenTox::Authorization.is_token_valid(subjectid)
        $logger.debug "authorized? >>#{ret}<< (token is in/valid), method: #{request_method}, URI: #{uri}, subjectid: #{subjectid}" unless ret
        ret
      elsif OpenTox::Authorization.authorize_exception?(uri, request_method)
        ret = OpenTox::Authorization.is_token_valid(subjectid)
        $logger.debug "authorized? >>#{ret}<< (uris is authorize exception, token is in/valid), method: #{request_method}, URI: #{uri}, subjectid: #{subjectid}" unless ret
        ret
      elsif $aa[:authorize_request].include?(request_method)
        ret = OpenTox::Authorization.authorize(uri, request_method, subjectid)
        $logger.debug "authorized? >>#{ret}<< (uri (not) authorized), method: #{request_method}, URI: #{uri}, subjectid: #{subjectid}" unless ret
        ret
      else
        $logger.error "invalid request/uri method: #{request_method}, URI: #{uri}, subjectid: #{subjectid}"
        false
      end
    end

    private
    def self.free_uri?(uri, request_method)
      if $aa[:free_uris]
        $aa[:free_uris].each do |request_methods,uris|
          if request_methods and uris and request_methods.include?(request_method.to_s)
            uris.each do |u|
              return true if u.match uri
            end
          end
        end
      end
      return false
    end

    def self.authorize_exception?(uri, request_method)
      if $aa[:authorize_exceptions]
        $aa[:authorize_exceptions].each do |request_methods,uris|
          if request_methods and uris and request_methods.include?(request_method.to_sym)
            uris.each do |u|
              return true if u.match uri
            end
          end
        end
      end
      return false
    end

  end
end
