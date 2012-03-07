require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'

class DatasetTest < Test::Unit::TestCase

=begin
  def test_post_get_delete
    service_uri = "http://ot-dev.in-silico.ch/dataset" 
    dataset = OpenTox::Dataset.create service_uri
    assert_match /#{service_uri}/, dataset.uri.to_s
      puts dataset.uri
    puts dataset.class
    puts dataset.to_yaml
    metadata =  dataset.metadata
    puts dataset.class
    assert_equal RDF::OT.Dataset, metadata[RDF.type]
    assert_equal dataset.uri, metadata[RDF::XSD.anyURI]
    dataset.delete
  end
  def test_all
    datasets = OpenTox::Dataset.all "http://ot-dev.in-silico.ch/dataset"
    assert_equal OpenTox::Dataset, datasets.first.class
  end

  def test_create
    d = OpenTox::Dataset.create "http://ot-dev.in-silico.ch/dataset"
    assert_equal OpenTox::Dataset, d.class
    puts d.delete
    assert_raise OpenTox::NotFoundError do
      puts d.get(:accept => 'application/x-yaml')
    end
  end
=end

  def test_create_from_file
    d = OpenTox::Dataset.from_file "http://ot-dev.in-silico.ch/dataset", "data/EPAFHM.mini.csv"
    assert_equal OpenTox::Dataset, d.class
    puts d.inspect
    
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
