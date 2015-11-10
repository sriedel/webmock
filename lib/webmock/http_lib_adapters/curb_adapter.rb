begin
  require 'curb'
rescue LoadError
  # curb not found
end

if defined?(Curl)
  WebMock::VersionChecker.new('Curb', Curl::CURB_VERSION, '0.7.16', '0.8.7').check_version!

  module WebMock
    module HttpLibAdapters
      class CurbAdapter < HttpLibAdapter
        adapter_for :curb

        OriginalCurlEasy  = Curl::Easy unless const_defined?(:OriginalCurlEasy)
        OriginalCurlMulti = Curl::Multi unless const_defined?(:OriginalCurlMulti)

        def self.enable!
          Curl.send(:remove_const, :Easy)
          Curl.send(:const_set, :Easy, Curl::WebMockCurlEasy)
          enable_multi!
        end

        def self.enable_multi!
          Curl.send(:remove_const, :Multi)
          Curl.send(:const_set, :Multi, Curl::WebMockCurlMulti)
        end

        def self.disable!
          Curl.send(:remove_const, :Easy)
          Curl.send(:const_set, :Easy, OriginalCurlEasy)
          disable_multi!
        end

        def self.disable_multi!
          Curl.send(:remove_const, :Multi)
          Curl.send(:const_set, :Multi, OriginalCurlMulti)
        end

        # Borrowed from Patron:
        # http://github.com/toland/patron/blob/master/lib/patron/response.rb
        def self.parse_header_string(header_string)
          status = nil
          headers = {}

          header_string.split(/\r\n/).each do |header|
            if header =~ %r|^HTTP/1.[01] \d\d\d (.*)|
              status = $1
              next
            end

            name, value = header.split(':', 2)
            next if name == nil && value == nil
            value.strip! if value
            if headers.has_key?( name )
              current_value = headers[name]
              headers[name] = [current_value] unless current_value.kind_of? Array
              headers[name] << value
            else
              headers[name] = value
            end
          end

          return status, headers
        end
      end
    end
  end

  module Curl
    class WebMockCurlEasy < Curl::Easy
      def curb_or_webmock
        request_signature = build_request_signature
        WebMock::RequestRegistry.instance.requested_signatures.put(request_signature)
        webmock_response = WebMock::StubRegistry.instance.response_for_request(request_signature)

        if webmock_response
          build_curb_response(webmock_response)
          WebMock::CallbackRegistry.invoke_callbacks( { :lib => :curb },
                                                      request_signature, 
                                                      webmock_response )
          invoke_curb_callbacks
          true
        elsif WebMock.net_connect_allowed?( request_signature.uri )
          # NOTE: must disable multi heere, since Curl::Easy is essentially a
          #       wrapper around Curl::Multi. However the WebMockCurlMulti 
          #       class is a wrapper around WebMockCurlEasy. Thus we'd have
          #       a circular reference if web requests are enabled but the
          #       mocked classes are active.
          #       
          #       The cleaner way would be to have the entire webmock logic in
          #       the WebMockCurlMulti class.
          #
          begin
            WebMock::HttpLibAdapters::CurbAdapter.disable_multi!
            res = yield
          ensure
            WebMock::HttpLibAdapters::CurbAdapter.enable_multi!
          end

          if WebMock::CallbackRegistry.any_callbacks?
            webmock_response = build_webmock_response
                                                        
            WebMock::CallbackRegistry.invoke_callbacks( { :lib => :curb, :real_request => true },
                                                        request_signature,
                                                        webmock_response)
          end
          res
        else
          raise WebMock::NetConnectNotAllowedError.new(request_signature)
        end
      end

      def build_request_signature
        method = @webmock_method.to_s.downcase.to_sym

        uri = WebMock::Util::URI.heuristic_parse(self.url)
        uri.path = uri.normalized_path.gsub("[^:]//","/")
        if self.userpwd
          uri.user, uri.password = self.userpwd.split( ":", 2 )
        else 
          uri.user     = self.username
          uri.password = self.password
        end

        request_body = case method
                         when :post then self.post_body || @post_body
                         when :put  then @put_data
                         else nil
                       end

        WebMock::RequestSignature.new( method, uri.to_s, :body    => request_body,
                                                         :headers => self.headers )
      end

      def build_curb_response( webmock_response )
        raise Curl::Err::TimeoutError if webmock_response.should_timeout
        webmock_response.raise_error_if_any

        @body_str = webmock_response.body
        @response_code = webmock_response.status[0]

        @header_str = "HTTP/1.1 #{webmock_response.status[0]} #{webmock_response.status[1]}\r\n"
        if webmock_response.headers
          @header_str << webmock_response.headers.map do |k,v|
                           "#{k}: #{v.is_a?(Array) ? v.join(", ") : v}"
                         end.join("\r\n")

          location = webmock_response.headers['Location']
          if self.follow_location? && location
            @last_effective_url = location
            webmock_follow_location(location)
          end

          @content_type      = webmock_response.headers["Content-Type"]
          @transfer_encoding = webmock_response.headers["Transfer-Encoding"]
        end

        @last_effective_url ||= self.url
      end

      def webmock_follow_location(location)
        first_url = self.url
        self.url = location

        curb_or_webmock do
          send( "http_#{@webmock_method}_without_webmock" )
        end

        self.url = first_url
      end

      def invoke_curb_callbacks
        @on_progress.call(0.0,1.0,0.0,1.0) if defined?( @on_progress )
        self.header_str.lines.each { |header_line| @on_header.call header_line } if defined?( @on_header )
        if defined?( @on_body )
          if chunked_response?
            self.body_str.each { |chunk| @on_body.call(chunk) }
          else
            @on_body.call(self.body_str)
          end
        end
        @on_complete.call(self) if defined?( @on_complete )

        case response_code
          when 200..299 then @on_success.call(self)                     if defined?( @on_success )
          when 400..499 then @on_missing.call(self, self.response_code) if defined?( @on_missing )
          when 500..599 then @on_failure.call(self, self.response_code) if defined?( @on_failure )
        end
      end

      def chunked_response?
        defined?( @transfer_encoding ) && @transfer_encoding == 'chunked' && self.body_str.respond_to?(:each)
      end

      def build_webmock_response
        status, headers =
         WebMock::HttpLibAdapters::CurbAdapter.parse_header_string(self.header_str)

        webmock_response = WebMock::Response.new
        webmock_response.status = [self.response_code, status]
        webmock_response.body = self.body_str
        webmock_response.headers = headers
        webmock_response
      end

      ###
      ### Mocks of Curl::Easy methods below here.
      ###

      def http(method)
        @webmock_method = method
        super
      end

      %w[ get head delete ].each do |verb|
        define_method "http_#{verb}" do
          @webmock_method = verb
          super()
        end
      end

      def http_put data = nil
        @webmock_method = :put
        @put_data = data if data
        super
      end
      alias put http_put

      def http_post *data
        @webmock_method = :post
        @post_body = data.join('&') if data && !data.empty?
        super
      end
      alias post http_post

      def perform
        @webmock_method ||= :get
        curb_or_webmock { super }
      end

      def put_data= data
        @webmock_method = :put
        @put_data = data
        super
      end

      def post_body= data
        @webmock_method = :post
        super
      end

      def delete= value
        @webmock_method = :delete if value
        super
      end

      def head= value
        @webmock_method = :head if value
        super
      end

      def body_str
        @body_str || super
      end
      alias body body_str

      def response_code
        @response_code || super
      end

      def header_str
        @header_str || super
      end
      alias head header_str

      def last_effective_url
        @last_effective_url || super
      end

      def content_type
        @content_type || super
      end

      %w[ success failure missing header body complete progress ].each do |callback|
        class_eval <<-METHOD, __FILE__, __LINE__
          def on_#{callback} &block
            @on_#{callback} = block
            super
          end
        METHOD
      end
    end

    class WebMockCurlMulti < Curl::Multi
      def perform
        @idle = false
        yield if block_given?

        requests.each do |request|
          yield if block_given?
          request.perform
        end

        yield if block_given?
        @idle = true
        true
      end

      def add( curl_easy )
        @requests ||= []
        @requests << curl_easy
        self
      end

      def remove( curl_easy )
        @requests.delete( curl_easy )
        self
      end

      def cancel!
        @requests.clear
        self
      end

      def requests
        @requests ||= []
      end

      def idle?
        @idle = true unless defined?( @idle )
      end
    end
  end
end
