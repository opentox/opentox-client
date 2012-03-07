class String
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end

module URI

  def self.task? uri
    uri =~ /task/ and URI.valid? uri
  end
  
  def self.dataset? uri, subjectid=nil
    uri =~ /dataset/ and URI.accessible? uri, subjectid=nil
  end
 
  def self.model? uri, subjectid=nil
    uri =~ /model/ and URI.accessible? uri, subjectid=nil
  end

  def self.accessible? uri, subjectid=nil
    if URI.task? uri
      # just ry to get a response, valid tasks may return codes > 400
      Net::HTTP.get_response(URI.parse(uri))
      true
    else
      Net::HTTP.get_response(URI.parse(uri)).code.to_i < 400
    end
  rescue
    false
  end

  def self.valid? uri
    u = URI::parse(uri)
    u.scheme!=nil and u.host!=nil
  rescue URI::InvalidURIError
    false
  end

  def self.to_object uri, wait=true

    # TODO add waiting task
    if task? uri and wait
      t = OpenTox::Task.new(uri)
      t.wait
      uri = t.resultURI
    end

    klass = 
    subjectid ? eval("#{self}.new(\"#{uri}\", #{subjectid})") : eval("#{self}.new(\"#{uri}\")")
  end

end

class File
  def mime_type 
    `file -ib #{self.path}`.chomp
  end
end
