require 'test/unit'
$LOAD_PATH << File.join(File.dirname(__FILE__),'..','lib')
require File.join File.dirname(__FILE__),'..','lib','opentox-client.rb'

class CompoundTest < Test::Unit::TestCase

  def setup
    @service_uri = "http://ot-dev.in-silico.ch/compound"
  end

  def test_compound_from_smiles_0
    c = OpenTox::Compound.from_smiles @service_uri, "F[B-](F)(F)F.[Na+]"
    assert_equal "InChI=1S/BF4.Na/c2-1(3,4)5;/q-1;+1", c.to_inchi
    assert_equal "[Na+].F[B-](F)(F)F", c.to_smiles # still does not work on 64bit machines
  end

  def test_compound_from_smiles_1
    c = OpenTox::Compound.from_smiles @service_uri, "CC(=O)CC(C)C#N"
    assert_equal "InChI=1S/C6H9NO/c1-5(4-7)3-6(2)8/h5H,3H2,1-2H3", c.to_inchi
    assert_equal "CC(CC(=O)C)C#N", c.to_smiles
  end

  def test_compound_from_name
    c = OpenTox::Compound.from_name @service_uri, "Benzene"
    assert_equal "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H", c.to_inchi
    assert_equal "c1ccccc1", c.to_smiles
  end

  def test_compound_from_smiles_2  
    c = OpenTox::Compound.from_smiles @service_uri, "N#[N+]C1=CC=CC=C1.F[B-](F)(F)F"
    assert_equal "InChI=1S/C6H5N2.BF4/c7-8-6-4-2-1-3-5-6;2-1(3,4)5/h1-5H;/q+1;-1", c.to_inchi
    assert_equal "N#[N+]c1ccccc1.F[B-](F)(F)F", c.to_smiles
  end

  def test_compound_from_inchi
    c = OpenTox::Compound.from_inchi @service_uri, "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"
    assert_equal "c1ccccc1", c.to_smiles
  end

  def test_compound_ambit
    c = OpenTox::Compound.new "http://apps.ideaconsult.net:8080/ambit2/compound/144036"
    assert_equal "InChI=1S/C6H11NO2/c1-3-5-6(4-2)7(8)9/h5H,3-4H2,1-2H3", c.to_inchi
    assert_equal "CCC=C(CC)[N+](=O)[O-]", c.to_smiles
  end

=begin
  def test_match_hits
    c = OpenTox::Compound.from_smiles @service_uri, "N=C=C1CCC(=F=FO)C1"
    assert_equal ({"FF"=>2, "CC"=>10, "C"=>6, "C1CCCC1"=>10, "C=C"=>2}), c.match_hits(['CC','F=F','C','C=C','FF','C1CCCC1','OO'])
  end
=end
end
