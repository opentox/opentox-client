module OpenTox

  if defined?($aa) and $aa.has_key?(:uri) and !$aa[:uri].nil?
    AA = $aa[:uri] 
  else
    AA = "https://opensso.in-silico.ch" #if not set in .opentox/conf/[SERVICE].rb
  end

  #Module for Authorization and Authentication
  #@example Authentication
  #  require "opentox-client"
  #  OpenTox::Authorization::AA = "https://opensso.in-silico.ch" #if not set in .opentox/conf/[SERVICE].rb
  #  OpenTox::Authorization.authenticate("username", "password")
  #  puts OpenTox::Authorization.authorize("http://example.uri/testpath/", "GET")
  #@see http://www.opentox.org/dev/apis/api-1.2/AA OpenTox A&A API 1.2 specification

  module Authorization

    #Helper Class to create and send default policies out of xml templates
    #@example Creating a default policy to a URI
    #  aa=OpenTox::Authorization::Helper.new(tok)
    #  xml=aa.get_xml('http://uri....')
    #  OpenTox::Authorization.create_policy(xml,tok)

    class Helper
      attr_accessor :user, :policy

      #Generates AA object - requires subjectid
      # @param [String] subjectid
      def initialize
        @user = Authorization.get_user
        @policy = Policies.new()
      end

      #Cleans AA Policies and loads default xml file into policy attribute
      #set uri and user, returns Policyfile(XML) for open-sso
      # @param uri [String] URI to create a policy for
      def get_xml(uri)
        @policy.drop_policies
        @policy.load_default_policy(@user, uri)
        return @policy.to_xml
      end

      #Loads and sends Policyfile(XML) to open-sso server
      # @param uri [String] URI to create a policy for
      def send(uri)
        xml = get_xml(uri)
        ret = false
        ret = Authorization.create_policy(xml)
        $logger.warn "Create policy on openSSO failed for URI: #{uri} subjectid: #{RestClientWrapper.subjectid}. Will try again." if !ret
        ret = Authorization.create_policy(xml) if !ret
        $logger.debug "Policy send with subjectid: #{RestClientWrapper.subjectid}"
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
    # @param user [String] Username
    # @param pw [String] Password
    # @return [Boolean] true if successful
    def self.authenticate(user, pw)
      return nil if !AA
      begin
        res = RestClientWrapper.post("#{AA}/auth/authenticate",{:username=>user, :password => pw},{:subjectid => ""}).sub("token.id=","").sub("\n","")
        if is_token_valid(res)
          RestClientWrapper.subjectid = res
          return true
        else
          bad_request_error "Authentication failed #{res.inspect}"
        end
      rescue
        bad_request_error "Authentication failed #{res.inspect}"
      end
    end

    #Logout on opensso. Make token invalid. Requires token
    # @param [String] subjectid the subjectid
    # @return [Boolean] true if logout is OK
    def self.logout(subjectid=RestClientWrapper.subjectid)
      begin
        out = RestClientWrapper.post("#{AA}/auth/logout", :subjectid => subjectid)
        return true unless is_token_valid(subjectid)
      rescue
        return false
      end
      return false
    end

    #Authorization against OpenSSO for a URI with request-method (action) [GET/POST/PUT/DELETE]
    # @param [String] uri URI to request
    # @param [String] action request method
    # @param [String] subjectid
    # @return [Boolean, nil]  returns true, false or nil (if authorization-request fails).
    def self.authorize(uri, action, subjectid=RestClientWrapper.subjectid)
      return true if !AA
      return true if RestClientWrapper.post("#{AA}/auth/authorize",{:subjectid => subjectid, :uri => uri, :action => action})== "boolean=true\n"
      return false
    end

    #Checks if a token is a valid token
    # @param [String]subjectid subjectid from openSSO session
    # @return [Boolean] subjectid is valid or not.
    def self.is_token_valid(subjectid=RestClientWrapper.subjectid)
      return true if !AA
      begin
        return true if RestClientWrapper.post("#{AA}/auth/isTokenValid",:tokenid => subjectid) == "boolean=true\n"
      rescue #do rescue because openSSO throws 401
        return false
      end
      return false
    end

    #Returns array with all policies of the token owner
    # @param [String]subjectid requires subjectid
    # @return [Array, nil] returns an Array of policy names or nil if request fails
    def self.list_policies
      begin
        out = RestClientWrapper.get("#{AA}/pol",nil)
        return out.split("\n")
      rescue
        return nil
      end
    end

    #Returns a policy in xml-format
    # @param policy [String] policyname
    # @param subjectid [String]
    # @return [String] XML of the policy
    def self.list_policy(policy)
      begin
        return RestClientWrapper.get("#{AA}/pol",nil,{:id => policy})
      rescue
        return nil
      end
    end

    # Lists policies alongside with affected uris
    # @param [String] subjectid
    # @return [Hash] keys: all policies of the subjectid owner, values: uris affected by those policies
    def self.list_policies_uris
      names = list_policies
      policies = {}
      names.each do |n|
        policies[n] = list_policy_uris n 
      end
      policies
    end

    # Lists policies alongside with affected uris
    # @param [String] subjectid
    # @return [Hash] keys: all policies of the subjectid owner, values: uris affected by those policies
    def self.list_policy_uris( policy )
      p = OpenTox::Policies.new
      p.load_xml( list_policy(policy) )
      p.uris
    end

    #Returns the owner (who created the first policy) of an URI
    # @param uri [String] URI
    # @param subjectid [String] subjectid
    # return [String, nil]owner,nil returns owner of the URI
    def self.get_uri_owner(uri)
      begin
        return RestClientWrapper.get("#{AA}/pol",nil,{:uri => uri}).sub("\n","")
      rescue
        return nil
      end
    end

    #Returns true or false if owner (who created the first policy) of an URI
    # @param uri [String] URI
    # @param subjectid [String]
    # return [Boolean]true,false status of ownership of the URI
    def self.uri_owner?(uri)
      get_uri_owner(uri) == get_user
    end

    #Checks if a policy exists to a URI. Requires URI and token.
    # @param uri [String] URI
    # @param subjectid [String]
    # return [Boolean]
    def self.uri_has_policy(uri)
      owner = get_uri_owner(uri)
      return true if owner and owner != "null"
      false
    end

    #List all policynames for a URI. Requires URI and token.
    # @param uri [String] URI
    # @param subjectid [String]
    # return [Array, nil] returns an Array of policy names or nil if request fails
    def self.list_uri_policies(uri)
      begin
        out = RestClientWrapper.get("#{AA}/pol",nil,{:uri => uri, :polnames => true})
        policies = []; notfirstline = false
        out.split("\n").each do |line|
          policies << line if notfirstline
          notfirstline = true
        end
        return policies
      rescue
        return nil
      end
    end

    #Sends a policy in xml-format to opensso server. Requires policy-xml and token.
    # @param policy [String] XML string of a policy
    # @param subjectid [String]
    # return [Boolean] returns true if policy is created
    def self.create_policy(policy)
      begin
        $logger.debug "OpenTox::Authorization.create_policy policy: #{policy[168,43]} with token: #{RestClientWrapper.subjectid} ."
        return true if RestClientWrapper.post("#{AA}/Pol/opensso-pol",policy, {:content_type =>  "application/xml"})
      rescue
        return false
      end
    end

    #Deletes a policy
    # @param policy [String] policyname
    # @param subjectid [String]
    # @return [Boolean,nil]
    def self.delete_policy(policy)
      begin
        $logger.debug "OpenTox::Authorization.delete_policy policy: #{policy} with token: #{RestClientWrapper.subjectid}"
        return true if RestClientWrapper.delete("#{AA}/pol",nil, {:id => policy})
      rescue
        return nil
      end
    end

    #Returns array of the LDAP-Groups of an user
    # @param [String]subjectid
    # @return [Array] gives array of LDAP groups of a user
    def self.list_user_groups(user)
      begin
        out = RestClientWrapper.post("#{AA}/opensso/identity/read", {:name => user, :admin => RestClientWrapper.subjectid, :attributes_names => "group"})
        grps = []
        out.split("\n").each do |line|
          grps << line.sub("identitydetails.group=","") if line.include?("identitydetails.group=")
        end
        return grps
      rescue
        []
      end
    end

    #Returns the owner (user id) of a token
    # @param [String]subjectid optional (normally only used for testing)
    # @return [String]user
    def self.get_user subjectid=RestClientWrapper.subjectid
      begin
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
      rescue
        nil
      end
    end

    #Send default policy with Authorization::Helper class
    # @param uri [String] URI
    # @param subjectid [String]
    def self.send_policy(uri)
      return true if !AA
      aa  = Authorization::Helper.new
      ret = aa.send(uri)
      $logger.debug "OpenTox::Authorization send policy for URI: #{uri} | subjectid: #{RestClientWrapper.subjectid} - policy created: #{ret}"
      ret
    end

    #Deletes all policies of an URI
    # @param uri [String] URI
    # @param subjectid [String]
    # @return [Boolean]
    def self.delete_policies_from_uri(uri)
      policies = list_uri_policies(uri)
      if policies
        policies.each do |policy|
          ret = delete_policy(policy)
          $logger.debug "OpenTox::Authorization delete policy: #{policy} - with result: #{ret}"
        end
      end
      return true
    end

    # Checks (if subjectid is valid) if a policy exist and create default policy if not
    # @param [String] uri
    # @param [String] subjectid
    # @return [Boolean] true if policy checked/created successfully (or no uri/subjectid given), false else
    def self.check_policy(uri)
      return true unless uri and RestClientWrapper.subjectid
      unless OpenTox::Authorization.is_token_valid(RestClientWrapper.subjectid)
        $logger.error "OpenTox::Authorization.check_policy, subjectid NOT valid: #{RestClientWrapper.subjectid}"
        return false
      end

      if !uri_has_policy(uri)
        # if no policy exists, create a policy, return result of send policy
        send_policy(uri)
      else
        # if policy exists check for POST rights
        if authorize(uri, "POST")
          true
       else
          $logger.error "OpenTox::Authorization.check_policy, already exists, but no POST-authorization with subjectid: #{RestClientWrapper.subjectid}"
          false
        end
      end
      true
    end

    class << self
      alias :token_valid? :is_token_valid
    end

    # Check Authorization for a resource (identified via URI) with method and subjectid.
    # @param uri [String] URI
    # @param request_method [String] GET, POST, PUT, DELETE
    # @param subjectid [String]
    # @return [Boolean] true if access granted, else otherwise
    def self.authorized?(uri, request_method)
      return true if !AA
      request_method = request_method.to_sym if request_method
      if $aa[:free_request].include?(request_method)
        true
      elsif OpenTox::Authorization.free_uri?(uri, request_method)
        true
      elsif $aa[:authenticate_request].include?(request_method)
        ret = OpenTox::Authorization.is_token_valid(RestClientWrapper.subjectid)
        $logger.debug "authorized? >>#{ret}<< (token is in/valid), method: #{request_method}, URI: #{uri}, subjectid: #{RestClientWrapper.subjectid}" unless ret
        ret
      elsif OpenTox::Authorization.authorize_exception?(uri, request_method)
        ret = OpenTox::Authorization.is_token_valid(RestClientWrapper.subjectid)
        $logger.debug "authorized? >>#{ret}<< (uris is authorize exception, token is in/valid), method: #{request_method}, URI: #{uri}, subjectid: #{RestClientWrapper.subjectid}" unless ret
        ret
      elsif $aa[:authorize_request].include?(request_method)
        ret = OpenTox::Authorization.authorize(uri, request_method)
        $logger.debug "authorized? >>#{ret}<< (uri (not) authorized), method: #{request_method}, URI: #{uri}, subjectid: #{RestClientWrapper.subjectid}" unless ret
        ret
      else
        $logger.error "invalid request/uri method: #{request_method}, URI: #{uri}, subjectid: #{RestClientWrapper.subjectid}"
        false
      end
    end

    private
    # extend class methods
    class << self
      # methods: free_uri and authorize_exception
      # @return [Boolean] checks if uri-method pair is included in $aa[:free_uri] or $aa[:authorize_exception]
      [:free_uri, :authorize_exception].each do |method|
        define_method "#{method}?".to_sym do |uri, request_method|
          if $aa["#{method}s".to_sym]
            $aa["#{method}s".to_sym].each do |request_methods, uris|
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
  end
end
