module OpenTox

  class Feature
    field :name, as: :title, type: String
    field :nominal, type: Boolean
    field :numeric, type: Boolean
    field :measured, type: Boolean
    field :calculated, type: Boolean
    field :supervised, type: Boolean
    field :source, as: :title, type: String
    #belongs_to :dataset
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
    field :smarts, type: String 
    #field :name, as: :smarts, type: String # causes warnings
    field :algorithm, type: String, default: "OpenTox::Algorithm::Descriptors.smarts_match"
    field :parameters, type: Hash, default: {:count => false}
    def initialize params
      super params
      nominal = true
    end
  end

  class FminerSmarts < Smarts
    field :pValue, type: Float
    field :effect, type: String
    field :dataset_id 
    def initialize params
      super params
      supervised = true
    end
  end

  class FingerprintSmarts < Smarts
    field :count, type: Integer
  end

  class NominalBioAssay < NominalFeature
    field :description, type: String
  end

  class NumericBioAssay < NumericFeature
    field :description, type: String
  end

  class PhysChemDescriptor < NumericFeature
    field :algorithm, type: String, default: "OpenTox::Algorithm::Descriptor.physchem"
    field :parameters, type: Hash
    field :creator, type: String
  end

end
