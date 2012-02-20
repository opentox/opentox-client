require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'

class RestTest < Test::Unit::TestCase

  def test_post_get_delete
    service_uri = "http://ot-dev.in-silico.ch/dataset" 
    dataset = OpenTox::Dataset.create service_uri
    assert_match /#{service_uri}/, dataset.uri.to_s
      puts dataset.uri
    puts dataset.class
    puts dataset.to_yaml
    metadata =  dataset.metadata
    puts dataset.class
=begin
    assert_equal RDF::OT.Dataset, metadata[RDF.type]
    assert_equal dataset.uri, metadata[RDF::XSD.anyURI]
=end
    dataset.delete
  end

end
