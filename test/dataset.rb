require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'
DATASET = "http://ot-dev.in-silico.ch/dataset"
DATA_DIR = File.join(File.dirname(__FILE__),"data")
# TODO: add subjectids


class DatasetTest < Test::Unit::TestCase

  def test_all
    datasets = OpenTox::Dataset.all DATASET
    assert_equal OpenTox::Dataset, datasets.first.class
  end

  def test_create_empty
    d = OpenTox::Dataset.create DATASET
    assert_equal OpenTox::Dataset, d.class
    assert_match /#{DATASET}/, d.uri.to_s
    d.delete
  end

  def test_create_from_file
    d = OpenTox::Dataset.from_file DATASET, File.join(DATA_DIR,"EPAFHM.mini.csv")
    assert_equal OpenTox::Dataset, d.class
    assert_equal d.uri, d[RDF::XSD.anyURI]
    assert_equal "EPAFHM.mini",  d.metadata[RDF::URI("http://purl.org/dc/elements/1.1/title")].first.to_s # DC.title is http://purl.org/dc/terms/title
    assert_equal "EPAFHM.mini",  d[RDF::URI("http://purl.org/dc/elements/1.1/title")]
    d.delete
    assert_raise OpenTox::NotFoundError do
      d.get
    end
  end

  def test_from_yaml
    @dataset = OpenTox::Dataset.from_file DATASET, File.join(DATA_DIR,"hamster_carcinogenicity.yaml")
    assert_equal OpenTox::Dataset, @dataset.class
    assert_equal "hamster_carcinogenicity", @dataset[RDF::URI("http://purl.org/dc/elements/1.1/title")]
    hamster_carc?
    @dataset.delete
  end

=begin
# TODO: fix (mime type??0 and add Egons example
  def test_sdf_with_multiple_features
    @dataset = OpenTox::Dataset.from_file DATASET, "#{DATA_DIR}/CPDBAS_v5c_1547_29Apr2008part.sdf"
    assert_equal OpenTox::Dataset, @dataset.class
    puts @dataset.features.size
    puts @dataset.compounds.size
    @dataset.delete
  end
=end

  def test_multicolumn_csv
    @dataset = OpenTox::Dataset.from_file DATASET, "#{DATA_DIR}/multicolumn.csv"
    assert_equal 5, @dataset.features.size
    assert_equal 4, @dataset.compounds.size
    @dataset.delete
  end

  def test_from_csv
    @dataset = OpenTox::Dataset.from_file DATASET, "#{DATA_DIR}/hamster_carcinogenicity.csv"
    assert_equal OpenTox::Dataset, @dataset.class
    hamster_carc?
    @dataset.delete
  end

=begin
  def test_save
    d = OpenTox::Dataset.create DATASET
    d.metadata
    d.metadata[RDF::DC.title] = "test"
    d.save
    # TODO: save does not work with datasets
    #puts d.response.code.inspect
    #assert_equal "test", d.metadata[RDF::DC.title] # should reload metadata
    d.delete
  end
=end
=begin
=end


  def hamster_carc?
    assert_kind_of OpenTox::Dataset, @dataset
    #require 'yaml'
    #puts @dataset.data_entries.to_yaml
    assert_equal 85, @dataset.data_entries.size
    assert_equal 85, @dataset.compounds.size
    assert_equal 1, @dataset.features.size
    assert_equal @dataset.uri, @dataset[RDF::XSD.anyURI]
  end
end
