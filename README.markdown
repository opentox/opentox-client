opentox-ruby-minimal
====================

Thin Ruby wrapper for the [OpenTox](http://www.opentox.org) REST API 

Installation
------------

  sudo gem install opentox-ruby-minimal

opentox-ruby depends on [rapper](http://librdf.org/raptor/rapper.html) for parsing OWL-DL in RDFXML format. 

Quickstart
----------

This example shows how to create a lazar model and predict a compound, it assumes that you have access to a working installation of OpenTox services with corresponding settings in $HOME/.opentox/config. Run the following code in irb or from a ruby script:

    require 'rubygems'
    require 'opentox-ruby'

    # Authenticate
    subjectid = OpenTox::Authorization.authenticate(USER,PASSWORD) 

    # Upload a dataset
    training_dataset = OpenTox::Dataset.create_from_csv_file(TRAINING_DATASET, subjectid)

    # Create a prediction model
    model_uri = OpenTox::Algorithm::Lazar.new.run({:dataset_uri => training_dataset.uri, :subjectid => subjectid}).to_s
    lazar = OpenTox::Model::Lazar.find model_uri, subjectid
    
    # Predict a compound
    compound = OpenTox::Compound.from_smiles("c1ccccc1NN")
    prediction_uri = lazar.run(:compound_uri => compound.uri, :subjectid => subjectid)
    prediction = OpenTox::LazarPrediction.find(prediction_uri, subjectid)
    puts prediction.to_yaml

[API documentation](http://rdoc.info/gems/opentox-ruby-minimal)
-------------------------------------------------------------------

Copyright
---------

Copyright (c) 2009-2011 Christoph Helma, Martin Guetlein, Micha Rautenberg, Andreas Maunz, David Vorgrimmler, Denis Gebele. See LICENSE for details.
