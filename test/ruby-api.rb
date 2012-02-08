require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'

class RubyAPITest < Test::Unit::TestCase

  def test_all
    datasets = OpenTox::Dataset.all "http://ot-dev.in-silico.ch/dataset"
    assert_equal OpenTox::Dataset, datasets.first.class
    assert_equal RDF::OT.Dataset, datasets.last.metadata[RDF.type]
  end
=begin

  def test_create
    d = OpenTox::Dataset.create "http://ot-dev.in-silico.ch/dataset"
    puts d.inspect
    assert_equal OpenTox::Dataset, d.class
    assert_equal RDF::OT.Dataset, d.metadata[RDF.type]
    d.delete
  end

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
