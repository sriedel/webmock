require 'spec_helper'

unless RUBY_PLATFORM =~ /java/
  describe "Curl::Multi" do
    subject { Curl::Multi.new }
    let( :easy ) { Curl::Easy.new( uri ) }
    let( :uri ) { "http://www.example.com" }

    describe "callbacks" do
      let( :uri_200 ) { "http://www.example.com/200" }
      let( :uri_300 ) { "http://www.example.com/300" }
      let( :uri_301 ) { "http://www.example.com/301" }
      let( :uri_400 ) { "http://www.example.com/400" }
      let( :uri_500 ) { "http://www.example.com/500" }
      let( :uri_redirect_target ) { "http://www.example.com/redirect_target" }

      let( :easy_200 ) { Curl::Easy.new( uri_200 ) }
      let( :easy_300 ) do
        Curl::Easy.new( uri_300 ) do |curl|
          curl.follow_location = false
        end
      end
      let( :easy_300_follow_redirect ) do
        Curl::Easy.new( uri_301 ) do |curl|
          curl.follow_location = true
        end
      end
      let( :easy_400 ) { Curl::Easy.new( uri_400 ) }
      let( :easy_500 ) { Curl::Easy.new( uri_500 ) }

      let( :response_200 ) { "I am a 200 response" }
      let( :response_300 ) { "I am a 300 response" }
      let( :response_301 ) { "I am a 301 response" }
      let( :response_redirect_target ) { "<?xml?><foo></foo>" }
      let( :response_400 ) { "I am a 400 response" }
      let( :response_500 ) { "I am a 500 response" }

      let( :easy_requests ) { [ easy_200, easy_300, easy_300_follow_redirect, easy_400, easy_500 ] }

      let( :on_success_called_for ) { [] }
      let( :on_failure_called_for ) { [] }
      let( :on_missing_called_for ) { [] }
      let( :on_redirect_called_for ) { [] }
      let( :on_body_called_for ) { {} }
      let( :on_header_called_for ) { Hash.new { |hash, key| hash[key] = Array.new } }
      let( :on_complete_called_for ) { [] }
      let( :on_progress_called_for ) { {} }
      let( :callbacks_called_for ) { Hash.new { |hash, key| hash[key] = Array.new } }

      before( :each ) do
        stub_request( :get, uri_200 ).
          to_return( :status  => 200,
                     :body    => response_200,
                     :headers => { "Content-Type" => "text/plain" } )
        stub_request( :get, uri_300 ).
          to_return( :status  => 302,
                     :body    => response_300,
                     :headers => { "Location" => uri_redirect_target } )
        stub_request( :get, uri_301 ).
          to_return( :status  => 301,
                     :body    => response_301,
                     :headers => { "Location" => uri_redirect_target } )
        stub_request( :get, uri_redirect_target ).
          to_return( :status => 200,
                     :body   => response_redirect_target,
                     :headers => { "Content-Type" => "application/xml" } )
        stub_request( :get, uri_400 ).
          to_return( :status  => 400,
                     :body    => response_400,
                     :headers => { "Content-Type" => "text/html", "X-Foo" => "Bar"} )
        stub_request( :get, uri_500 ).
          to_return( :status  => 500,
                     :body    => response_500,
                     :headers => { "Content-Type" => "application/json", "X-Bar" => "Baz" } )
        # stub_request( :get, uri_timeout ).to_timeout

        easy_requests.each do |easy|
          subject.add( easy )
          easy.on_redirect do |*args|
            on_redirect_called_for << easy
            callbacks_called_for[easy] << :on_redirect
          end
          easy.on_success do |*args|
            on_success_called_for << easy.url
            callbacks_called_for[easy] << :on_success
          end
          easy.on_failure do |*args|
            on_failure_called_for << easy.url
            callbacks_called_for[easy] << :on_failure
          end
          easy.on_missing do |*args|
            on_missing_called_for << easy.url
            callbacks_called_for[easy] << :on_missing
          end
          easy.on_body do |body_data|
            on_body_called_for[easy.url] = body_data
            callbacks_called_for[easy] << :on_body
          end
          easy.on_header do |header_data|
            on_header_called_for[easy.url] << header_data
            callbacks_called_for[easy] << :on_header
          end
          easy.on_complete do |completed_request|
            on_complete_called_for << completed_request.url
            callbacks_called_for[easy] << :on_complete
          end
          easy.on_progress do |dl_total, dl_now, ul_total, ul_now|
            on_progress_called_for[easy] = [dl_total, dl_now, ul_total, ul_now]
            callbacks_called_for[easy] << :on_progress
          end
        end
      end

      it "should call on_success for each request that receives a 2xx response" do
        subject.perform
        on_success_called_for.should =~ [ easy_200.url, easy_300_follow_redirect.url, uri_redirect_target ]
      end

      it "should call on_missing for each request that receives a 4xx response" do
        subject.perform
        on_missing_called_for.should == [ easy_400.url ]
      end

      it "should call on_failure for each request that receives a 5xx response" do
        subject.perform
        on_failure_called_for.should == [ easy_500.url ]
      end

      it "should call on_body for a request when it receives body data" do
        subject.perform
        on_body_called_for.keys.should =~ [ easy_200.url, easy_300.url, easy_300_follow_redirect.url, easy_400.url, easy_500.url, uri_redirect_target ]
        on_body_called_for[easy_200.url].should == response_200
        on_body_called_for[easy_300.url].should == response_300
        on_body_called_for[easy_300_follow_redirect.url].should == response_redirect_target
        on_body_called_for[easy_400.url].should == response_400
        on_body_called_for[easy_500.url].should == response_500
        on_body_called_for[uri_redirect_target].should == response_redirect_target
      end

      it "should call on_header for a request for each response header that is returned" do
        subject.perform
        on_header_called_for.keys.should =~ [ easy_200.url, easy_300.url, easy_300_follow_redirect.url, easy_400.url, easy_500.url, uri_redirect_target ]
        on_header_called_for[easy_200.url].should == [ "HTTP/1.1 200 \r\n", "Content-Type: text/plain" ]
        on_header_called_for[easy_300.url].should == [ "HTTP/1.1 302 \r\n", "Location: #{uri_redirect_target}" ]
        on_header_called_for[easy_300_follow_redirect.url].should == [ "HTTP/1.1 200 \r\n", "Content-Type: application/xml" ]
        on_header_called_for[uri_redirect_target].should == [ "HTTP/1.1 200 \r\n", "Content-Type: application/xml" ]
        on_header_called_for[easy_400.url].should == [ "HTTP/1.1 400 \r\n", "Content-Type: text/html\r\n", "X-Foo: Bar" ]
        on_header_called_for[easy_500.url].should == [ "HTTP/1.1 500 \r\n", "Content-Type: application/json\r\n", "X-Bar: Baz" ]
      end

      it "should call on_complete for requests that complete" do
        subject.perform
        on_complete_called_for.should =~ [ easy_200.url, easy_300.url, easy_300_follow_redirect.url, uri_redirect_target, easy_400.url, easy_500.url ]
      end

      it "should call on_progress for requests when it receives body data" do
        subject.perform
        on_progress_called_for.keys.should =~ [ easy_200, easy_300, easy_300_follow_redirect, easy_400, easy_500 ]
        on_progress_called_for[easy_200].should == [ 0.0, 1.0, 0.0, 1.0 ]
        on_progress_called_for[easy_300].should == [ 0.0, 1.0, 0.0, 1.0 ]
        on_progress_called_for[easy_300_follow_redirect].should == [ 0.0, 1.0, 0.0, 1.0 ]
        on_progress_called_for[easy_400].should == [ 0.0, 1.0, 0.0, 1.0 ]
        on_progress_called_for[easy_500].should == [ 0.0, 1.0, 0.0, 1.0 ]
      end

      it "should call the callbacks in the correct order for a successful request" do
        subject.perform
        callbacks_called_for[easy_200].should == [ :on_progress, :on_header, :on_header, :on_body, :on_complete, :on_success ]
      end

      it "should call the callbacks in the correct order for a failed request" do
        subject.perform
        callbacks_called_for[easy_500].should == [ :on_progress, :on_header, :on_header, :on_header, :on_body, :on_complete, :on_failure ]
      end

      it "should call the callbacks in the correct order for a missing request" do
        subject.perform
        callbacks_called_for[easy_400].should == [ :on_progress, :on_header, :on_header, :on_header, :on_body, :on_complete, :on_missing ]
      end

      it "should call the callbacks in the correct order for a redirected request" do
        subject.perform
        callbacks_called_for[easy_300].should == [ :on_progress, :on_header, :on_header, :on_body, :on_complete]
      end

      it "should call the callbacks in the correct order for a request that returns the reidrect" do
        subject.perform
        callbacks_called_for[easy_300_follow_redirect].should == [ :on_progress, :on_header, :on_header, :on_body, :on_complete, :on_success, :on_progress, :on_header, :on_header, :on_body, :on_complete, :on_success ]
      end
    end

    describe ".http" do
      let( :uri_get ) { "http://www.example.com/get" }
      let( :uri_post ) { "http://www.example.com/post" }
      let( :uri_head ) { "http://www.example.com/head" }
      let( :uri_delete ) { "http://www.example.com/delete" }
      let( :uri_put ) { "http://www.example.com/put" }

      let( :response_get ) { "foobar" }
      let( :response_code_get ) { 200 }

      let( :response_post ) { "barbaz" }
      let( :response_code_post ) { 201 }

      let( :response_head ) { "quux" }
      let( :response_code_head ) { 200 }

      let( :response_delete ) { "" }
      let( :response_code_delete ) { 204 }

      let( :response_put ) { "blubb" }
      let( :response_code_put ) { 202 }

      let( :post_body ) { "foo=bar&baz=quux" }
      let( :put_data ) { "putting data" }

      let( :results ) { {} }

      let( :on_success_lambda ) do
        lambda do |easy|
           results[easy.url] = { :status => easy.response_code,
                                 :body   => easy.body_str }
        end
      end
      let( :on_body_lambda ) do
        lambda do |body_data|
          results[uri_post] ||= {}
          results[uri_post][:body] ||= ""
          results[uri_post][:body] << body_data
        end
      end

      before( :each ) do
        stub_request( :get, uri_get ).
          to_return( :status => response_code_get, :body => response_get, :headers => {} )

        stub_request( :post, uri_post ).
          with( :body => post_body ).
          to_return( :status => response_code_post, :body => response_post, :headers => {} )

        stub_request( :head, uri_head ).
          to_return( :status => response_code_head, :body => response_head, :headers => {} )

        stub_request( :delete, uri_delete ).
          to_return( :status => response_code_delete, :body => response_delete, :headers => {} )

        stub_request( :put, uri_put ).
          with( :body => put_data ).
          to_return( :status => response_code_put, :body => response_put, :headers => {} )
      end

      context "without multi options" do
        it "should process all the requests as expected" do
          Curl::Multi.http( [ { :url         => uri_get,
                                :method      => :get,
                                :on_success  => on_success_lambda },
                              { :url         => uri_post,
                                :method      => :post,
                                :post_fields => { 'foo' => 'bar', 'baz' => 'quux' },
                                :on_success  => on_success_lambda,
                                :on_body     => on_body_lambda },
                              { :url         => uri_head,
                                :method      => :head,
                                :on_success  => on_success_lambda },
                              { :url         => uri_delete,
                                :method      => :delete,
                                :on_success  => on_success_lambda },
                              { :url         => uri_put,
                                :put_data    => put_data,
                                :method      => :put,
                                :on_success  => on_success_lambda } ] ) do |easy, code, method|
            case method
              when :get    then easy.url.should == uri_get
              when :head   then easy.url.should == uri_head
              when :delete then easy.url.should == uri_delete
              when :post   then easy.url.should == uri_post
              when :put    then easy.url.should == uri_put
              else raise "Unexpected method #{method.inspect} encountered"
            end
          end

          result_get = results[uri_get]
          result_get[:status].should == response_code_get
          result_get[:body].should == response_get

          result_post = results[uri_post]
          result_post[:status].should == response_code_post
          result_post[:body].should == response_post

          result_head = results[uri_head]
          result_head[:status].should == response_code_head
          result_head[:body].should == response_head

          result_delete = results[uri_delete]
          result_delete[:status].should == response_code_delete
          result_delete[:body].should == response_delete

          result_put = results[uri_put]
          result_put[:status].should == response_code_put
          result_put[:body].should == response_put
        end
      end

      context "with multi options" do
        let( :max_connections ) { 100 }
        let( :on_success_lambda ) do
          lambda do |easy|
            results[easy.url] = { :status => easy.response_code,
                                  :body   => easy.body_str }
          end
        end

        it "should process all the requests as expected with the multi options applied" do
          Curl::Multi.http( [ { :url         => uri_get,
                                :method      => :get,
                                :on_success  => on_success_lambda },
                              { :url         => uri_post,
                                :method      => :post,
                                :post_fields => { 'foo' => 'bar', 'baz' => 'quux' },
                                :on_success  => on_success_lambda,
                                :on_body     => on_body_lambda },
                              { :url         => uri_head,
                                :method      => :head,
                                :on_success  => on_success_lambda },
                              { :url         => uri_delete,
                                :method      => :delete,
                                :on_success  => on_success_lambda },
                              { :url         => uri_put,
                                :put_data    => put_data,
                                :method      => :put,
                                :on_success  => on_success_lambda } ],
                              :pipeline     => true,
                              :max_connects => max_connections ) do |easy, code, method|
            case method
              when :get    then easy.url.should == uri_get
              when :head   then easy.url.should == uri_head
              when :delete then easy.url.should == uri_delete
              when :post   then easy.url.should == uri_post
              when :put    then easy.url.should == uri_put
              else raise "Unexpected method #{method.inspect} encountered"
            end
          end
          # FIXME: How can we access the generated multi?
          #        Curl::Easy#multi in a callback doesn't work...

          result_get = results[uri_get]
          result_get[:status].should == response_code_get
          result_get[:body].should == response_get

          result_post = results[uri_post]
          result_post[:status].should == response_code_post
          result_post[:body].should == response_post

          result_head = results[uri_head]
          result_head[:status].should == response_code_head
          result_head[:body].should == response_head

          result_delete = results[uri_delete]
          result_delete[:status].should == response_code_delete
          result_delete[:body].should == response_delete

          result_put = results[uri_put]
          result_put[:status].should == response_code_put
          result_put[:body].should == response_put
        end
      end
    end

    describe ".get" do
      let( :uri_1 ) { "http://www.example.com/1" }
      let( :uri_2 ) { "http://www.example.com/2" }
      let( :uri_3 ) { "http://www.example.com/3" }

      let( :response_1 ) { "foobar" }
      let( :response_code_1 ) { 200 }

      let( :response_2 ) { "barbaz" }
      let( :response_code_2 ) { 201 }

      let( :response_3 ) { "quux" }
      let( :response_code_3 ) { 204 }

      let( :results ) { {} }

      before( :each ) do
        stub_request( :get, uri_1 ).
          to_return( :status => response_code_1, :body => response_1, :headers => {} )

        stub_request( :get, uri_2 ).
          to_return( :status => response_code_2, :body => response_2, :headers => {} )

        stub_request( :get, uri_3 ).
          to_return( :status => response_code_3, :body => response_3, :headers => {} )
      end

      it "should process all the requests as expected" do
        Curl::Multi.get( [ uri_1, uri_2, uri_3 ] ) do |easy|
          case easy.url
            when uri_1
              easy.response_code.should == response_code_1
              easy.body_str.should == response_1

            when uri_2
              easy.response_code.should == response_code_2
              easy.body_str.should == response_2

            when uri_3
              easy.response_code.should == response_code_3
              easy.body_str.should == response_3

            else raise "Unexpected url #{easy.url.inspect} received in the result"
          end
        end
      end
    end

    describe ".post" do
      let( :uri_1 ) { "http://www.example.com/1" }
      let( :uri_2 ) { "http://www.example.com/2" }
      let( :uri_3 ) { "http://www.example.com/3" }

      let( :post_fields1 ) { { "foo1" => "bar1", "baz1" => "quux1" } }
      let( :post_fields2 ) { { "foo2" => "bar2", "baz2" => "quux2" } }
      let( :post_fields3 ) { { "foo3" => "bar3", "baz3" => "quux3" } }

      let( :response_1 ) { "foobar" }
      let( :response_code_1 ) { 200 }

      let( :response_2 ) { "barbaz" }
      let( :response_code_2 ) { 201 }

      let( :response_3 ) { "quux" }
      let( :response_code_3 ) { 204 }

      let( :results ) { {} }

      before( :each ) do
        stub_request( :post, uri_1 ).
          with( :body => "foo1=bar1&baz1=quux1" ).
          to_return( :status => response_code_1, :body => response_1, :headers => {} )

        stub_request( :post, uri_2 ).
          with( :body => "foo2=bar2&baz2=quux2" ).
          to_return( :status => response_code_2, :body => response_2, :headers => {} )

        stub_request( :post, uri_3 ).
          with( :body => "foo3=bar3&baz3=quux3" ).
          to_return( :status => response_code_3, :body => response_3, :headers => {} )
      end

      it "should process all the requests as expected" do
        Curl::Multi.post( [ { :url         => uri_1,
                              :post_fields => post_fields1 },
                            { :url         => uri_2,
                              :post_fields => post_fields2 },
                            { :url         => uri_3,
                              :post_fields => post_fields3 } ] ) do |easy|
          case easy.url
            when uri_1
              easy.response_code.should == response_code_1
              easy.body_str.should == response_1

            when uri_2
              easy.response_code.should == response_code_2
              easy.body_str.should == response_2

            when uri_3
              easy.response_code.should == response_code_3
              easy.body_str.should == response_3

            else raise "Unexpected url #{easy.url.inspect} received in the result"
          end
        end
      end
    end

    describe ".put" do
      let( :uri_1 ) { "http://www.example.com/1" }
      let( :uri_2 ) { "http://www.example.com/2" }
      let( :uri_3 ) { "http://www.example.com/3" }

      let( :put_data1 ) { "foo" }
      let( :put_data2 ) { "bar" }
      let( :put_data3 ) { "baz" }

      let( :response_1 ) { "foobar" }
      let( :response_code_1 ) { 200 }

      let( :response_2 ) { "barbaz" }
      let( :response_code_2 ) { 201 }

      let( :response_3 ) { "quux" }
      let( :response_code_3 ) { 204 }

      let( :results ) { {} }

      before( :each ) do
        stub_request( :put, uri_1 ).
          with( :body => put_data1 ).
          to_return( :status => response_code_1, :body => response_1, :headers => {} )

        stub_request( :put, uri_2 ).
          with( :body => put_data2 ).
          to_return( :status => response_code_2, :body => response_2, :headers => {} )

        stub_request( :put, uri_3 ).
          with( :body => put_data3 ).
          to_return( :status => response_code_3, :body => response_3, :headers => {} )
      end

      it "should process all the requests as expected" do
        Curl::Multi.put( [ { :url      => uri_1,
                             :put_data => put_data1 },
                           { :url      => uri_2,
                             :put_data => put_data2 },
                           { :url      => uri_3,
                             :put_data => put_data3 } ] ) do |easy|
          case easy.url
            when uri_1
              easy.response_code.should == response_code_1
              easy.body_str.should == response_1

            when uri_2
              easy.response_code.should == response_code_2
              easy.body_str.should == response_2

            when uri_3
              easy.response_code.should == response_code_3
              easy.body_str.should == response_3

            else raise "Unexpected url #{easy.url.inspect} received in the result"
          end
        end
      end
    end

    describe "#add" do
      it "should add the request to the requests processed by Curl::Multi" do
        expect do
          subject.add( easy )
        end.to change { subject.requests }.from( [] ).to( [ easy ] )
      end
    end

    describe "#remove" do
      it "should remove the request from the requests processed by Curl::Multi" do
        subject.add( easy )
        expect do
          subject.remove( easy )
        end.to change { subject.requests }.from( [ easy ] ).to( [] )
      end
    end

    describe "the #perform method" do
      let( :uri_1 ) { "http://www1.example.com" }
      let( :uri_2 ) { "https://www2.example.com/path/to/form" }

      let( :response_1 ) { "foobar" }
      let( :response_code_1 ) { 200 }

      let( :response_2 ) { "barbaz" }
      let( :response_code_2 ) { 201 }

      let( :post_body ) { [ "foo", "bar", { "baz" => "quux" } ] }
      let( :easy_1 ) do
        Curl::Easy.new( uri_1 )
      end

      let( :easy_2 ) do
        Curl::Easy.new( uri_2 ) do |curl|
          curl.headers["Content-Type"] = "application/json"
          curl.post_body = post_body.to_json
        end
      end

      before( :each ) do
        stub_request( :get, uri_1 ).
          to_return( :status => response_code_1, :body => response_1, :headers => {} )

        stub_request( :post, uri_2 ).
          with( :body => post_body.to_json, :headers => { "Content-Type" => "application/json" } ).
          to_return( :status => response_code_2, :body => response_2, :headers => {} )
      end

      it "should perform the added requests" do
        results = {}

        easy_1.on_complete do |result_handle|
          results[result_handle.url] = { :status => result_handle.response_code,
                                         :body   => result_handle.body_str }
        end

        easy_2.on_body do |body_data|
          results[easy_2.url] ||= {}
          results[easy_2.url][:body] ||= ""
          results[easy_2.url][:body] << body_data
        end

        easy_2.on_complete do |result_handle|
          results[result_handle.url] ||= {}
          results[result_handle.url][:status] = result_handle.response_code
        end

        subject.add( easy_1 )
        subject.add( easy_2 )
        subject.perform

        result_1 = results[easy_1.url]
        result_1[:status].should == response_code_1
        result_1[:body].should == response_1

        result_2 = results[easy_2.url]
        result_2[:status].should == response_code_2
        result_2[:body].should == response_2
      end

      it "should call the given block during idle times" do
        completed_requests = 0
        idle_loop_calls = 0

        easy_1.on_complete do
          completed_requests += 1
        end

        easy_2.on_complete do
          completed_requests += 1
        end

        subject.add( easy_1 )
        subject.add( easy_2 )

        subject.perform do
          idle_loop_calls += 1
        end

        idle_loop_calls.should == completed_requests + 1
      end
    end

    describe "the #idle? method" do
      let( :response ) { "foobar" }
      let( :response_code ) { 200 }

      before( :each ) do
        stub_request( :get, uri ).
          to_return( :status => response_code, :body => response, :headers => {} )
      end

      it "should be true before Curl::Multi#perform is called" do
        subject.should be_idle
      end

      it "should be true after Curl::Multi#perform is called" do
        subject.perform
        subject.should be_idle
      end

      it "should be false after an easy handler was added" do
        subject.add( easy )
        subject.should_not be_idle
      end

      it "should be false while Curl::Multi#perform is processing" do
        subject.add( easy )
        subject.perform do
          subject.should_not be_idle
        end
      end
    end
  end
end
