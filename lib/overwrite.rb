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

  def self.compound? uri
    uri =~ /compound/ and URI.valid? uri
  end

  def self.task? uri
    #TODO remove localhost
    (uri =~ /task/ or uri =~ /localhost/) and URI.valid? uri
  end
  
  def self.dataset? uri, subjectid=nil
    uri =~ /dataset/ and URI.accessible? uri, subjectid=nil
  end

  def self.model? uri, subjectid=nil
    uri =~ /model/ and URI.accessible? uri, subjectid=nil
  end

  def self.ssl? uri, subjectid=nil
    URI.parse(uri).instance_of? URI::HTTPS
  end

  def self.accessible?(uri, subjectid=nil)
    if URI.task? uri or URI.compound? uri
      # just try to get a response, valid tasks may return codes > 400
      Net::HTTP.get_response(URI.parse(uri))
      true
    else
      Net::HTTP.get_response(URI.parse(uri + (subjectid ? "?subjectid=#{CGI.escape subjectid}" : ""))).code.to_i < 400
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

end

class File
  def mime_type 
    `file -ib #{self.path}`.chomp
  end
end

# overwrite backtick operator to catch system errors
module Kernel

  # Override raises an error if _cmd_ returns a non-zero exit status.
  # Returns stdout if _cmd_ succeeds.  Note that these are simply concatenated; STDERR is not inline.
  def ` cmd
    stdout, stderr = ''
    status = Open4::popen4(cmd) do |pid, stdin_stream, stdout_stream, stderr_stream|
      stdout = stdout_stream.read
      stderr = stderr_stream.read
    end
    internal_server_error "`" + cmd + "` failed.\n" + stdout + stderr if !status.success?
    return stdout
  rescue
    internal_server_error $!.message
  end

end

