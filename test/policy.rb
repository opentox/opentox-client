require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.expand_path(File.join(File.dirname(__FILE__),'..','lib','opentox-client.rb'))

TEST_URI    = "http://only_a_test/test/" + rand(1000000).to_s
USER_TYPE   = "LDAPUsers"
USER_VALUE  = "uid=guest,ou=people,dc=opentox,dc=org"
USER_GROUP  = "member"
GROUP_TYPE  = "LDAPGroups"
GROUP_VALUE = "cn=member,ou=groups,dc=opentox,dc=org"
POLICY_NAME = "test_policy_#{rand(100000)}"
RULE_NAME = "test_rule_#{rand(100000)}"
SUBJECT_NAME = "test_subject_#{rand(100000)}"

AA ||= "https://opensso.in-silico.ch"
AA_USER = "guest"
AA_PASS = "guest"

@@subjectid = OpenTox::Authorization.authenticate(AA_USER,AA_PASS)

class PolicyTest < Test::Unit::TestCase

  def test_01_class
    policies = OpenTox::Policies.new()
    assert_equal(policies.class, OpenTox::Policies)
    assert_kind_of Array, policies.names
    assert_kind_of Array, policies.uris
    assert_kind_of Array, policies.names
  end

  def test_02_subclasses
    policies = OpenTox::Policies.new()
    policies.new_policy(POLICY_NAME)
    assert_equal(policies.names[0], POLICY_NAME)
    assert_equal(policies.policies[policies.names[0]].class, OpenTox::Policy)
    policy = policies.policies[policies.names[0]]
    policy.rule.name = RULE_NAME
    policy.uri = TEST_URI
    assert_equal(policy.rule.class, OpenTox::Policy::Rule)
    assert_equal(policy.rule.name, RULE_NAME)
    assert_equal(policy.rule.uri, TEST_URI)
    assert_equal(policy.uri, TEST_URI)
    policy.subject.name = SUBJECT_NAME
    policy.type = USER_TYPE
    policy.value = USER_VALUE
    assert_equal(policy.subject.class, OpenTox::Policy::Subject)
    assert_equal(policy.subject.name, SUBJECT_NAME)
    assert_equal(policy.subject.type, USER_TYPE)
    assert_equal(policy.type, USER_TYPE)
    assert_equal(policy.subject.value, USER_VALUE)
    assert_equal(policy.value, USER_VALUE)
  end

  def test_03_read_readwrite
    policies = OpenTox::Policies.new()
    policies.new_policy(POLICY_NAME)
    policy = policies.policies[policies.names[0]]
    policy.rule.name = RULE_NAME
    policy.uri = TEST_URI
    policy.rule.get = "allow"
    assert policy.rule.read
    assert !policy.rule.readwrite
    policy.rule.post = "allow"
    policy.rule.put = "allow"
    assert !policy.rule.read
    assert policy.rule.readwrite
  end

  def test_04_group_user
    policies = OpenTox::Policies.new()
    policies.load_default_policy(AA_USER, TEST_URI, "member")
    assert_equal "member", policies.policies["policy_group"].group
    assert_equal AA_USER, policies.policies["policy_user"].user
  end

  def test_05_DN
    policies = OpenTox::Policies.new()
    policies.new_policy(POLICY_NAME)
    policy = policies.policies[policies.names[0]]
    policy.set_ot_user(AA_USER)
    assert_equal USER_VALUE, policy.value
    assert_equal USER_TYPE, policy.type
    policy.set_ot_group(USER_GROUP)
    assert_equal GROUP_VALUE, policy.value
    assert_equal GROUP_TYPE, policy.type
  end

  def test_06_load_xml_and_check_defaults
    policies = OpenTox::Policies.new()
    xml = File.read(File.join(File.dirname(__FILE__), "../lib/templates/default_policy.xml"))
    policies.load_xml(xml)
    # check user policy
    policy = policies.policies["policy_user"]
    assert policy.name == "policy_user"
    assert policy.rule.name == "rule_user"
    assert policy.rule.uri == "uri"
    assert policy.rule.get == "allow"
    assert policy.rule.post == "allow"
    assert policy.rule.delete == "allow"
    assert policy.rule.put == "allow"
    assert policy.subject_group == "subjects_user"
    assert policy.subject.name == "subject_user"
    assert policy.subject.type == USER_TYPE
    assert policy.subject.value == USER_VALUE
    # check group policy
    policy = policies.policies["policy_group"]
    assert policy.name == "policy_group"
    assert policy.rule.name == "rule_group"
    assert policy.rule.uri == "uri"
    assert policy.rule.get == "allow"
    assert !policy.rule.post
    assert !policy.rule.delete
    assert !policy.rule.put
    assert policy.subject_group == "subjects_group"
    assert policy.subject.name == "subject_group"
    assert policy.subject.type == GROUP_TYPE
    assert policy.subject.value == GROUP_VALUE
  end

end