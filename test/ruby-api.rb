$LOAD_PATH << File.expand_path( File.dirname(__FILE__) + '/../lib' )
require 'rubygems'
require 'opentox-ruby-minimal.rb'
require 'test/unit'

class RubyAPITest < Test::Unit::TestCase

  def test_create
    d = OpenTox::Dataset.create "http://ot-dev.in-silico.ch/dataset"#, {RDF::DC.title => "test dataset"}
    assert_equal OpenTox::Dataset, d.class
    assert_equal RDF::OT.Dataset, d.metadata[RDF.type]
  end

  def test_save
  end

end
