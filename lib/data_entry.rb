module OpenTox

  class DataEntry
    #field :feature_id, type: BSON::ObjectId
    #field :compound_id, type: BSON::ObjectId
    # Kludge because csv import removes type information
    field :feature_id, type: String
    field :compound_id, type: String
    field :value
    field :warnings, type: String
    field :unit, type: String
    store_in collection: "data_entries"

    # preferred method for the insertion of data entries
    # @example DataEntry.find_or_create compound,feature,value
    # @param compound [OpenTox::Compound]
    # @param feature [OpenTox::Feature]
    # @param value
    def self.find_or_create compound, feature, value
      self.find_or_create_by(
        :compound_id => compound.id,
        :feature_id => feature.id,
        :value => value
      )
    end

    # preferred method for accessing values
    # @example DataEntry[compound,feature]
    # @param compound [OpenTox::Compound]
    # @param feature [OpenTox::Feature]
    # @return value
    def self.[](compound,feature)
      self.where(:compound_id => compound.id.to_s, :feature_id => feature.id.to_s).distinct(:value).first
    end
  end
end
