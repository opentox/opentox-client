# defaults to stderr, may be changed to file output (e.g in opentox-service)
$logger = OTLogger.new(STDERR) 
$logger.level = Logger::DEBUG
Mongo::Logger.logger = $logger
Mongo::Logger.logger.level = Logger::WARN 
$mongo = Mongo::Client.new($mongodb[:uri])

module OpenTox

  # Ruby interface
  attr_accessor :data

  # Create a new OpenTox object 
  # @param id [optional,String] ID
  # @return [OpenTox] OpenTox object
  def initialize 
    @data = {}
    @data["type"] = type
  end

  def created_at
    @data["_id"].generation_time
  end

  # Object metadata (lazy loading)
  # @return [Hash] Object metadata
  def metadata 
    get if exists?
    @data
  end

  # Metadata values 
  # @param predicate [String] Predicate URI
  # @return [Array, String] Predicate value(s)
  def [](predicate)
    predicate = predicate.to_s
    return nil if @data[predicate].nil?
    @data[predicate].size == 1 ? @data[predicate].first : @data[predicate]
  end

  # Set a metadata entry
  # @param predicate [String] Predicate URI
  # @param values [Array, String] Predicate value(s)
  def []=(predicate,values)
    predicate = predicate.to_s
    values.is_a?(Array) ? @data[predicate] = [values].flatten : @data[predicate] = values
  end

  def id
    @data["_id"]
  end

  def exists? 
    nr_items = $mongo[collection].find(:_id => @data["_id"]).count
    nr_items > 0 ? true : false
  end

  # Get object from webservice
  # @param [String,optional] mime_type
  def get 
    resource_not_found_error("#{@data[:type]} with ID #{@data["_id"]} not found.") unless exists?
    @data = $mongo[collection].find(:_id => @data["_id"]).first
  end

  def save
    @data["_id"] = $mongo[collection].insert_one(@data).inserted_id
  end

  # partial update 
  def update metadata
    $mongo[collection].find(:_id => @data["_id"]).find_one_and_replace('$set' => metadata)
  end

  # Save object at webservice (replace or create object)
  def put 
    #@data.delete("_id") # to enable updates
    $mongo[collection].find(:_id => @data["_id"]).find_one_and_replace(@data, :upsert => true)
  end

  # Delete object at webservice
  def delete 
    $mongo[collection].find(:_id => @data["_id"]).find_one_and_delete
  end

  # @return [String] converts OpenTox object into html document (by first converting it to a string)
  def to_html
    @data.to_json.to_html
  end

  def type
    self.class.to_s.split('::').last
  end

  def collection
    type.downcase
  end

  # short access for metadata keys title, description and type
  [ :title , :description ].each do |method|
    send :define_method, method do 
      self[method]
    end
    send :define_method, "#{method}=" do |value|
      self[method] = value
    end
  end

  # define class methods within module
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def subjectid
      RestClientWrapper.subjectid
    end
    def subjectid=(subjectid)
      RestClientWrapper.subjectid = subjectid
    end
  end

  # create default OpenTox classes with class methods
  # (defined in opentox-client.rb)
  CLASSES.each do |klass|
    c = Class.new do
      include OpenTox

      def self.all 
        $mongo[collection].find.collect do |data|
          f = self.new
          f.data = data
          f
        end
      end

      def self.find_id id
        self.find(:_id => id)
      end

      #@example fetching a model
      #  OpenTox::Model.find(<model-id>) -> model-object
      def self.find metadata
        f = self.new
        items = $mongo[collection].find metadata
        items.count > 0 ? f.data = items.first : f = nil
        f
      end

      def self.create metadata
        object = self.new 
        object.data = metadata
        object.save
        object.get
        object
      end

      def self.find_or_create metadata
        search = metadata
        search.delete("_id")
        ids = $mongo[collection].find(search).distinct(:_id)
        ids.empty? ? self.create(metadata) : self.find_id(ids.first)
      end

      private 
      def self.collection
        self.to_s.split('::').last.downcase
      end
    end
    OpenTox.const_set klass,c
  end

end

