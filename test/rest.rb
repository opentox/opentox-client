require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'

class RestTest < Test::Unit::TestCase

  def test_post_get_delete
    uri = "http://ot-dev.in-silico.ch/dataset" 
    dataset = OpenTox::Dataset.create uri
    assert_match /#{uri}/, dataset.uri.to_s
    metadata =  dataset.metadata
    assert_equal RDF::OT.Dataset, metadata[RDF.type]
    assert_equal dataset.uri, metadata[RDF::XSD.anyURI]
    dataset.delete
  end

end
