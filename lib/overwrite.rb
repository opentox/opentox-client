class Object
  # An object is blank if it's false, empty, or a whitespace string.
  # For example, "", "   ", +nil+, [], and {} are all blank.
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def numeric?
    true if Float(self) rescue false
  end
end

module Enumerable
  def duplicates
    inject({}) {|h,v| h[v]=h[v].to_i+1; h}.reject{|k,v| v==1}.keys
  end
end

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

  def self.ssl? uri, subjectid=nil
    URI.parse(uri).instance_of? URI::HTTPS
  end

  def self.accessible?(uri, subjectid=nil)
    if URI.task? uri or URI.compound? uri
      # just try to get a response, valid tasks may return codes > 400
      Net::HTTP.get_response(URI.parse(uri))
      true
    else
      parsed_uri = URI.parse(uri + (subjectid ? "?subjectid=#{CGI.escape subjectid}" : ""))
      unless URI.ssl? uri      
        Net::HTTP.get_response(parsed_uri).code.to_i < 400
      else
        http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        request = Net::HTTP::Get.new(parsed_uri.request_uri)
        http.request(request).code.to_i < 400
      end
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
    internal_server_error "`" + cmd + "` failed.\n" + stdout + stderr unless status.success?
    return stdout
  rescue
    internal_server_error $!.message 
  end

end


class Array

  # Sum of an array for Arrays
  # @param [Array] Array of arrays
  # @return [Integer] Sum of size of array elements
  def sum_size
    self.inject(0) { |s,a|
      if a.respond_to?('size')
        s+=a.size
      else
        internal_server_error "No size available: #{a.inspect}"
      end
    }
  end

  # For symbolic features
  # @param [Array] Array to test.
  # @return [Boolean] Whether the array has just one unique value.
  def zero_variance?
    return self.uniq.size == 1
  end


end

