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
    uri =~ /task/ and URI.valid? uri
  end
  
  def self.dataset? uri, subjectid=nil
    uri =~ /dataset/ and URI.accessible? uri, subjectid=nil
  end
 
  def self.model? uri, subjectid=nil
    uri =~ /model/ and URI.accessible? uri, subjectid=nil
  end

  def self.accessible? uri, subjectid=nil
    if URI.task? uri or URI.compound? uri
      # just try to get a response, valid tasks may return codes > 400
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
    raise stderr.strip if !status.success?
    return stdout
  rescue Exception 
    internal_server_error $!
  end

  alias_method :system!, :system

  def system cmd
    `#{cmd}`
    return true
  end
end

class Array
  def short_backtrace
    short = []
    each do |c|
      break if c =~ /sinatra\/base/
      short << c
    end
    short.join("\n")
  end
end
