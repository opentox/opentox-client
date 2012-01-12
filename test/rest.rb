$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/../lib' )
require 'rubygems'
require 'opentox-ruby-minimal.rb'
require 'test/unit'

class RestTest < Test::Unit::TestCase

  def test_post_get_delete
    uristring = "http://ot-dev.in-silico.ch/dataset" 
    uri = uristring
    dataset_service = OpenTox::Dataset.new uri
    assert_match /#{uristring}/, dataset_service.get
    dataset_uri = dataset_service.post 
    assert_match /#{uristring}/, dataset_uri.to_s
    dataset = OpenTox::Dataset.new dataset_uri
    assert_equal dataset_uri, dataset.uri
    metadata =  dataset.metadata
    assert_equal RDF::OT.Dataset, metadata[RDF.type]
    assert_equal dataset.uri, metadata[RDF::XSD.anyURI]
    dataset.delete
  end

end
