module OpenTox
  require "rexml/document"

  #Module for policy-processing
  # @see also http://www.opentox.org/dev/apis/api-1.2/AA for opentox API specs
  # Class Policies corresponds to <policies> container of an xml-policy-fle
  class Policies

    #Hash for policy objects see {Policy Policy}
    attr_accessor :policies, :name

    def initialize()
      @policies = {}
    end

    #create new policy instance with name
    # @param [String]name of the policy
    def new_policy(name)
      @policies[name] = Policy.new(name)
    end

    #drop a specific policy in a policies instance
    # @param [String]name of the policy
    # @return [Boolean]
    def drop_policy(name)
      return true if @policies.delete(name)
    end

    #drop all policies in a policies instance
    def drop_policies
      @policies.each do |name, policy|
        drop_policy(name)
      end
      return true
    end

    # @return [Array] set of arrays affected by policies
    def uris
      @policies.collect{ |k,v| v.uri }.flatten.uniq
    end

    #list all policy names in a policies instance
    # @return [Array]
    def names
      out = []
      @policies.each do |name, policy|
        out << name
      end
      return out
    end

    # Loads a default policy template in a policies instance
    # @param [String]user username in LDAP string of user policy: 'uid=<user>,ou=people,dc=opentox,dc=org'
    # @param [String]uri URI
    # @param [String]group groupname in LDAP string of group policy: 'cn=<group>,ou=groups,dc=opentox,dc=org'
    def load_default_policy(user, uri, group="member")
      template = case user
        when "guest", "anonymous" then "default_guest_policy"
        else "default_policy"
      end
      xml = get_xml_template(template)
      self.load_xml(xml)
      datestring = Time.now.strftime("%Y-%m-%d-%H-%M-%S-x") + rand(1000).to_s

      @policies["policy_user"].name = "policy_user_#{user}_#{datestring}"
      @policies["policy_user"].rule.uri = uri
      @policies["policy_user"].rule.name = "rule_user_#{user}_#{datestring}"
      @policies["policy_user"].subject.name = "subject_user_#{user}_#{datestring}"
      @policies["policy_user"].subject.value = "uid=#{user},ou=people,dc=opentox,dc=org"
      @policies["policy_user"].subject_group = "subjects_user_#{user}_#{datestring}"

      @policies["policy_group"].name = "policy_group_#{group}_#{datestring}"
      @policies["policy_group"].rule.uri = uri
      @policies["policy_group"].rule.name = "rule_group_#{group}_#{datestring}"
      @policies["policy_group"].subject.name = "subject_group_#{group}_#{datestring}"
      @policies["policy_group"].subject.value = "cn=#{group},ou=groups,dc=opentox,dc=org"
      @policies["policy_group"].subject_group = "subjects_#{group}_#{datestring}"
      return true
    end

    def get_xml_template(template)
      File.read(File.join(File.dirname(__FILE__), "templates/#{template}.xml"))
    end

    #loads a xml template
    def load_xml(xml)
      rexml = REXML::Document.new(xml)
      rexml.elements.each("Policies/Policy") do |pol|    #Policies
        policy_name = pol.attributes["name"]
        new_policy(policy_name)
        #@policies[policy_name] = Policy.new(policy_name)
        rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Rule") do |r|    #Rules
          rule_name = r.attributes["name"]
          uri = rexml.elements["Policies/Policy[@name='#{policy_name}']/Rule[@name='#{rule_name}']/ResourceName"].attributes["name"]
          @policies[policy_name].rule.name = rule_name
          @policies[policy_name].uri = uri
          rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Rule[@name='#{rule_name}']/AttributeValuePair") do |attribute_pairs|
            action=nil; value=nil;
            attribute_pairs.each_element do |elem|
              action = elem.attributes["name"] if elem.attributes["name"]
              value = elem.text if elem.text
            end
            if action and value
              case action
              when "GET"
                @policies[policy_name].rule.get    = value
              when "POST"
                @policies[policy_name].rule.post   = value
              when "PUT"
                @policies[policy_name].rule.put    = value
              when "DELETE"
                @policies[policy_name].rule.delete = value
              end
            end
          end
        end
        rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Subjects") do |subjects|    #Subjects
          @policies[policy_name].subject_group = subjects.attributes["name"]
          rexml.elements.each("Policies/Policy[@name='#{policy_name}']/Subjects[@name='#{@policies[policy_name].subject_group}']/Subject") do |s|    #Subject
            subject_name  = s.attributes["name"]
            subject_type  = s.attributes["type"]
            subject_value = rexml.elements["Policies/Policy[@name='#{policy_name}']/Subjects[@name='#{@policies[policy_name].subject_group}']/Subject[@name='#{subject_name}']/AttributeValuePair/Value"].text
            if subject_name and subject_type and subject_value
              @policies[policy_name].subject.name = subject_name
              @policies[policy_name].type = subject_type
              @policies[policy_name].value = subject_value
            end
          end
        end
      end
    end

    #generates xml from policies instance
    def to_xml
      doc = REXML::Document.new()
      doc <<  REXML::DocType.new("Policies", "PUBLIC  \"-//Sun Java System Access Manager7.1 2006Q3\n Admin CLI DTD//EN\" \"jar://com/sun/identity/policy/policyAdmin.dtd\"")
      doc.add_element(REXML::Element.new("Policies"))

      @policies.each do |name, pol|
        policy = REXML::Element.new("Policy")
        policy.attributes["name"] = pol.name
        policy.attributes["referralPolicy"] = false
        policy.attributes["active"] = true
        rule = @policies[name].rule
        out_rule = REXML::Element.new("Rule")
        out_rule.attributes["name"] = rule.name
        servicename = REXML::Element.new("ServiceName")
        servicename.attributes["name"]="iPlanetAMWebAgentService"
        out_rule.add_element(servicename)
        rescourcename = REXML::Element.new("ResourceName")
        rescourcename.attributes["name"] = rule.uri
        out_rule.add_element(rescourcename)

        ["get","post","delete","put"].each do |act|
          if rule.method(act).call
            attribute = REXML::Element.new("Attribute")
            attribute.attributes["name"] = act.upcase
            attributevaluepair = REXML::Element.new("AttributeValuePair")
            attributevaluepair.add_element(attribute)
            attributevalue = REXML::Element.new("Value")
            attributevaluepair.add_element(attributevalue)
            attributevalue.add_text REXML::Text.new(rule.method(act).call)
            out_rule.add_element(attributevaluepair)
          end
        end
        policy.add_element(out_rule)

        subjects = REXML::Element.new("Subjects")
        subjects.attributes["name"] = pol.subject_group
        subjects.attributes["description"] = ""
        subj = @policies[name].subject.name
        subject = REXML::Element.new("Subject")
        subject.attributes["name"] = pol.subject.name
        subject.attributes["type"] = pol.subject.type
        subject.attributes["includeType"] = "inclusive"
        attributevaluepair = REXML::Element.new("AttributeValuePair")
        attribute = REXML::Element.new("Attribute")
        attribute.attributes["name"] = "Values"
        attributevaluepair.add_element(attribute)
        attributevalue = REXML::Element.new("Value")
        attributevalue.add_text REXML::Text.new(pol.subject.value)
        attributevaluepair.add_element(attributevalue)
        subject.add_element(attributevaluepair)
        subjects.add_element(subject)
        policy.add_element(subjects)
        doc.root.add_element(policy)
      end
      out = ""
      doc.write(out, 2)
      return out
    end

  end

  #single policy in a {Policies Policies} instance
  class Policy

    attr_accessor :name, :rule, :subject_group, :subject, :value, :type, :uri, :group, :user

    def initialize(name)
      @name = name
      @rule = Rule.new("#{name}_rule", nil)
      @subject_group = "#{name}_subjects"
      @subject = Subject.new("#{name}_subject", nil, nil)
    end

    # Subject type LDAPUsers or LDAPGroups
    def type
      @subject.type
    end

    # Set subject type <LDAPUsers, LDAPGroups>
    # @param [String],type
    def type=(type)
      @subject.type = type
    end

    # returns LDAP Distinguished Name (DN) e.g. uid=username,ou=people,dc=opentox,dc=org or cn=membergroup,ou=groups,dc=opentox,dc=org
    def value
      @subject.value
    end

    # sets LDAP Distinguished Name (DN) for policy e.g.
    # @param [String],LDAPString
    def value=(value)
      @subject.value = value
    end

    # uri affected by policy
    # @return uri affected by policy
    def uri
      @rule.uri
    end

    # sets uri affected by policy
    # @param [String] set URI
    def uri=(uri)
      @rule.uri = uri
    end

    # Get the groupname from within the LDAP Distinguished Name (DN)
    def group
      return false if !value && type != "LDAPGroups"
      value.split(",").each{|part| return part.gsub("cn=","") if part.match("cn=")}
    end

    # Get the username from within the LDAP Distinguished Name (DN)
    def user
      return false if !value && type != "LDAPUsers"
      value.split(",").each{|part| return part.gsub("uid=","") if part.match("uid=")}
    end

    # helper method sets value and type to opentox LDAP Distinguished Name (DN) of a user
    # @param [String]Username set a username into LDAP DN
    def set_ot_user(username)
      self.value = "uid=#{username},ou=people,dc=opentox,dc=org"
      self.type = "LDAPUsers"
      true
    end

    # @param [String]Username set a groupname into LDAP DN
    def set_ot_group(groupname)
      self.value = "cn=#{groupname},ou=groups,dc=opentox,dc=org"
      self.type = "LDAPGroups"
      true
    end

    # policyrule
    # sets the permission for REST actions (GET, POST, PUT, DELETE) of a specific URI to allow/deny/nil
    class Rule

      attr_accessor :name, :uri, :get, :post, :put, :delete, :read, :readwrite

      def initialize(name, uri)
        @name = name
        @uri = uri
      end

      #Set Rule attribute for request-method GET
      # @param [String]value (allow,deny,nil)
      def get=(value)
        @get = check_value(value, @get)
      end

      #Set Rule attribute for request-method POST
      # @param [String]value (allow,deny,nil)
      def post=(value)
        @post = check_value(value, @post)
      end

      #Set Rule attribute for request-method DELETE
      # @param [String]value (allow,deny,nil)
      def delete=(value)
        @delete = check_value(value, @delete)
      end

      #Set Rule attribute for request-method PUT
      # @param [String]value (allow,deny,nil)
      def put=(value)
        @put = check_value(value, @put)
      end

      # read getter method
      def read
        return true if @get == "allow" && (@put == "deny" || !@put) && (@post == "deny" || !@post)
      end

      # readwrite getter method
      def readwrite
        return true if @get == "allow" && @put == "allow" && @post == "allow"
      end

      # Set(true case) or remove read(GET=allow) permissions.
      # @param [Boolean]value (true,false)
      def read=(value)
        if value
          @get = "allow"; @put = nil; @post = nil
        else
          @get = nil; @put = nil; @post = nil
        end
      end

      # Set(true case) or remove readwrite(GET=allow,POST=allow,PUT=allow) permissions.
      # @param [Boolean]value (true,false)
      def readwrite=(value)
        if value
          @get = "allow"; @put = "allow"; @post = "allow"
        else
          @get = nil; @put = nil; @post = nil
        end
      end

      private
      #checks if value is allow, deny or nil. returns old value if not valid.
      def check_value(new_value, old_value)
        return (new_value=="allow" || new_value=="deny" || new_value==nil) ? new_value : old_value
      end
    end

    # Subject of a policy
    # name(subjectname), type('LDAPUsers' or 'LDAPGroups'), value(LDAP DN e.G.:'uid=guest,ou=people,dc=opentox,dc=org')
    class Subject

      attr_accessor :name, :type, :value

      def initialize(name, type, value)
        @name  = name
        @type  = type
        @value = value
      end
    end
  end
end
