require "base64"
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

  # encloses URI in text with with link tag
  # @return [String] new text with marked links
  def link_urls
    self.gsub(/(?i)http(s?):\/\/[^\r\n\s']*/, '<a href="\0">\0</a>')
  end

  # produces a html page for making web services browser friendly
  # format of text (=string params) is preserved (e.g. line breaks)
  # urls are marked as links
  #
  # @param [String] text this is the actual content, 
  # @param [optional,String] related_links info on related resources
  # @param [optional,String] description general info
  # @param [optional,Array] post_command, infos for the post operation, object defined below
  # @return [String] html page
  def to_html(related_links=nil, description=nil, png_image=nil  )
    
    # TODO add title as parameter
    title = nil #$sinatra.to($sinatra.request.env['PATH_INFO'], :full) if $sinatra
    html = "<html>"
    html << "<title>"+title+"</title>" if title
    #html += "<img src=\""+OT_LOGO+"\"><\/img><body>"
      
    html << "<h3>Description</h3><pre><p>"+description.link_urls+"</p></pre>" if description
    html << "<h3>Related links</h3><pre><p>"+related_links.link_urls+"</p></pre>" if related_links
    html << "<h3>Content</h3>" if description || related_links
    html << "<pre><p style=\"padding:15px; border:10px solid \#B9DCFF\">"
    html << "<img src=\"data:image/png;base64,#{Base64.encode64(png_image)}\">\n" if png_image
    html << self.link_urls
    html << "</p></pre></body></html>"
    html
  end
  
  def uri?
    URI.valid?(self)
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

module Kernel

  # overwrite backtick operator to catch system errors
  # Override raises an error if _cmd_ returns a non-zero exit status. CH: I do not understand this comment
  # Returns stdout if _cmd_ succeeds.  Note that these are simply concatenated; STDERR is not inline. CH: I do not understand this comment
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

  def wait_for_task uri
    if URI.task?(uri) 
      t = OpenTox::Task.new uri
      t.wait
      unless t.completed?
        begin # handle known (i.e. OpenTox) errors
          error = OpenTox::RestClientWrapper.known_errors.select{|error| error[:code] == t.code}.first
          error ? error_method = error[:method] : error_method = :internal_server_error
          report = t.error_report
          report ? error_message = report[RDF::OT.message] : error_message = $!.message
          Object.send(error_method,error_message,t.uri)
        rescue
          internal_server_error "#{$!.message}\n#{$!.backtrace}", t.uri
        end
      end
      uri = t.resultURI
    end
    uri
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

