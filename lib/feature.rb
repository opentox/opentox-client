module OpenTox

  class Feature
    field :name, as: :title, type: String
    field :nominal, type: Boolean
    field :numeric, type: Boolean
    field :measured, type: Boolean
    field :calculated, type: Boolean
    field :supervised, type: Boolean
    field :source, as: :title, type: String
  end

  class NominalFeature < Feature
    field :accept_values, type: Array
    def initialize params
      super params
      nominal = true
    end
  end

  class NumericFeature < Feature
    def initialize params
      super params
      numeric = true
    end
  end

  class Smarts < NominalFeature
    field :name, as: :smarts, type: String # causes warnings
    field :algorithm, type: String, default: "OpenTox::Algorithm::Descriptors.smarts_match"
    field :parameters, type: Hash, default: {:count => false}
    def initialize params
      super params
      nominal = true
    end
  end

  class FminerSmarts < Smarts
    field :training_algorithm, type: String
    field :training_compound_ids, type: Array
    field :training_feature_id, type: BSON::ObjectId
    field :training_parameters, type: Hash
    def initialize params
      super params
      supervised = true
    end
  end

  class NominalBioAssay < NominalFeature
    field :description, type: String
  end

  class NumericBioAssay < NumericFeature
    field :description, type: String
  end

  class PhysChemDescriptor < NumericFeature
    field :algorithm, type: String
    field :parameters, type: Hash
  end

end
