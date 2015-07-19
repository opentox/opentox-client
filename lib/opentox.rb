module OpenTox

  # Ruby interface

  # create default OpenTox classes (defined in opentox-client.rb)
  # provides Mongoid's query and persistence methods
  # http://mongoid.org/en/mongoid/docs/persistence.html
  # http://mongoid.org/en/mongoid/docs/querying.html
  CLASSES.each do |klass|
    c = Class.new do
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: klass.downcase.pluralize

      field :title, type: String
      field :description, type: String
      field :parameters, type: Array, default: []
      field :creator, type: String

      # TODO check if needed
      def self.subjectid
        RestClientWrapper.subjectid
      end
      def self.subjectid=(subjectid)
        RestClientWrapper.subjectid = subjectid
      end
    end
    OpenTox.const_set klass,c
  end

  def type
    self.class.to_s.split('::').last
  end

  # Serialisation

  # @return [String] converts OpenTox object into html document (by first converting it to a string)
  def to_html
    self.to_json.to_html
  end

end

