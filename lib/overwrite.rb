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
    Net::HTTP.get_response(URI.parse(uri))
    true
  rescue
    false
  end

  def self.valid? uri
    u = URI::parse(uri)
    u.scheme!=nil and u.host!=nil
  rescue URI::InvalidURIError
    false
  end

end

