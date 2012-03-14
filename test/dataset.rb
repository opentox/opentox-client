require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'

class DatasetTest < Test::Unit::TestCase

  def test_all
    datasets = OpenTox::Dataset.all "http://ot-dev.in-silico.ch/dataset"
    assert_equal OpenTox::Dataset, datasets.first.class
  end

  def test_create_empty
    service_uri = "http://ot-dev.in-silico.ch/dataset" 
    d = OpenTox::Dataset.create service_uri
    assert_equal OpenTox::Dataset, d.class
    assert_match /#{service_uri}/, d.uri.to_s
    d.delete
  end

  def test_create_from_file
    d = OpenTox::Dataset.from_file "http://ot-dev.in-silico.ch/dataset", File.join(File.dirname(__FILE__),"data","EPAFHM.mini.csv")
    assert_equal OpenTox::Dataset, d.class
    assert_equal d.uri, d[RDF::XSD.anyURI]
    assert_equal "EPAFHM.mini",  d.metadata[RDF::URI("http://purl.org/dc/elements/1.1/title")].to_s # DC.title is http://purl.org/dc/terms/title
    d.delete
    assert_raise OpenTox::NotFoundError do
      d.get
    end
  end

=begin
  def test_save
    d = OpenTox::Dataset.create "http://ot-dev.in-silico.ch/dataset"
    d.metadata
    d.metadata[RDF::DC.title] = "test"
    d.save
    # TODO: save does not work with datasets
    #puts d.response.code.inspect
    #assert_equal "test", d.metadata[RDF::DC.title] # should reload metadata
    d.delete
  end
=end


end
