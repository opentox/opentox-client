require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'

class ErrorTest < Test::Unit::TestCase

  def test_bad_request
    object = OpenTox::Feature.new "http://this-is-a/fantasy/url"
    assert_raise OpenTox::NotFoundError do
      response = object.get
    end
  end

  def test_error_methods
    assert_raise OpenTox::NotFoundError do
      not_found_error "This is a test"
    end
  end

  def test_exception
    assert_raise Exception do
      raise Exception.new "Basic Exception"
    end
  end

  def test_backtick
    assert_raise OpenTox::InternalServerError do
      `this call will not work`
    end
    assert_raise OpenTox::InternalServerError do
      `ls inexisting_directory`
    end
  end

end
