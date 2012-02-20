#TODO: switch services to 1.2
RDF::OT =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.2#'
RDF::OT1 =  RDF::Vocabulary.new 'http://www.opentox.org/api/1.1#'
RDF::OTA =  RDF::Vocabulary.new 'http://www.opentox.org/algorithmTypes.owl#'
SERVICES = ["Compound", "Feature", "Dataset", "Algorithm", "Model", "Validation", "Task"]

# not working
RestClient.add_before_execution_proc do |req, params|
  params[:subjectid] = @subjectid
end

class String
  def to_object
    # TODO: fix, this is unsafe
    self =~ /dataset/ ? uri = File.join(self.chomp,"metadata") : uri = self.chomp
    #raise "#{uri} is not a valid URI." unless RDF::URI.new(uri).uri? 
    raise "#{uri} is not a valid URI." unless uri.uri? 
    RDF::Reader.open(uri) do |reader|
      reader.each_statement do |statement|
        if statement.predicate == RDF.type and statement.subject == uri
          klass = "OpenTox::#{statement.object.to_s.split("#").last}"
          object = eval "#{klass}.new \"#{uri}\""
        end
      end
    end
    # fallback: guess class from uri
    # TODO: fix services and remove
    unless object
      case uri
      when /compound/
        object = OpenTox::Compound.new uri
      when /feature/
        object = OpenTox::Feature.new uri
      when /dataset/
        object = OpenTox::Dataset.new uri.sub(/\/metadata/,'')
      when /algorithm/
        object = OpenTox::Algorithm.new uri
      when /model/
        object = OpenTox::Model.new uri
      when /validation/
        object = OpenTox::Validation.new uri
      when /task/
        object = OpenTox::Task.new uri
      else
        raise "Class for #{uri} not found."
      end
    end
    if object.class == Task # wait for tasks
      object.wait_for_completion
      object = object.result_uri.to_s.to_object
    end
    object
  end

  def uri?
    begin
      Net::HTTP.get_response(URI.parse(self))
      true
    rescue
      false
    end
  end
end


# defaults to stderr, may be changed to file output
$logger = OTLogger.new(STDERR) # no rotation
$logger.level = Logger::DEBUG

module OpenTox

  attr_accessor :subjectid, :uri, :response
  attr_writer :metadata

  def initialize uri=nil, subjectid=nil
    @uri = uri.chomp
    @subjectid = subjectid
  end

  # Ruby interface

  def metadata reload=true
    if reload
      @metadata = {}
      begin
        #puts self.class
        #self.kind_of?(OpenTox::Dataset) ? uri = URI.join(@uri,"metadata") : uri = @uri
        #$logger.debug uri
        RDF::Reader.open(uri) do |reader|
          reader.each_statement do |statement|
            @metadata[statement.predicate] = statement.object if statement.subject == @uri
          end
        end
      rescue
        $logger.error "Cannot read RDF metadata from #{@uri}: #{$!}.\n#{$!.backtrace.join("\n")}"
        raise
      end
    end
    @metadata
  end

  def save
    rdf = RDF::Writer.for(:rdfxml).buffer do |writer|
      @metadata.each { |p,o| writer << RDF::Statement.new(RDF::URI.new(@uri), p, o) }
    end
    post rdf, { :content_type => 'application/rdf+xml'}
  end

  # REST API
  def get params={}
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.get @uri, params
  end

  def post payload={}, params={}
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.post(@uri.to_s, payload, params)
    begin
      @response.to_s.to_object
    rescue
      @response
    end
  end

  def put payload={}, params={} 
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.put(@uri.to_s, payload, params)
  end

  def delete params={}
    params[:subjectid] ||= @subjectid
    params[:accept] ||= 'application/rdf+xml'
    @response = RestClient.delete(@uri.to_s,:subjectid => @subjectid)
  end

  # class methods
  module ClassMethods

    def create service_uri, subjectid=nil
      uri = RestClient.post(service_uri, {}, :subjectid => subjectid).chomp
      subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")
    end

    def from_file service_uri, file, subjectid=nil
      RestClient.post(service_uri, :file => File.new(file), :subjectid => subjectid).chomp.to_object
    end

    def all service_uri, subjectid=nil
      uris = RestClient.get(service_uri, {:accept => 'text/uri-list'}).split("\n").compact
      uris.collect{|uri| subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")}
    end

  end

  # create default classes
  SERVICES.each do |s|
    eval "class #{s}
      include OpenTox
      extend OpenTox::ClassMethods
    end"
  end

end

