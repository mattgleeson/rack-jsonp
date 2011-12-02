require 'rack'
require 'multi_json'

module Rack
  # A Rack middleware for providing JSON-P support.
  #
  # Adapted from Flinn Mueller (http://actsasflinn.com/).
  #
  class JSONP

    def initialize(app, options = {})
      @app = app
      @carriage_return = options[:carriage_return] || false
      @callback_param = options[:callback_param] || 'callback'
      @return_errors = options[:return_errors] || false
    end

    # Proxies the request to the application, stripping out the JSON-P
    # callback method and padding the response with the appropriate callback
    # format.
    #
    # Changes nothing if no <tt>callback</tt> param is specified.
    #
    def call(env)
      # remove the callback and _ parameters BEFORE calling the backend, so
      # that caching middleware does not store a copy for each value of the
      # callback parameter
      request = Rack::Request.new(env)
      callback = request.params.delete(@callback_param)
      env['QUERY_STRING'] = env['QUERY_STRING'].split("&").delete_if{|param|
        param =~ /^(_|#{@callback_param})=/
      }.join("&")

      response = @app.call(env)
      status, headers, body = response

      if callback && (headers['Content-Type'] =~ /json/i or return_error?(response))
        body = pad(callback, response)
        headers['Content-Length'] = body.first.bytesize.to_s
        headers['Content-Type'] = 'application/javascript'
        if return_error?(response)
          status = 200 # error is tunneled through the JSONP call
        end
      elsif @carriage_return && headers['Content-Type'] =~ /json/i
        # add a \n after the response if this is a json (not JSONP) response
        body = carriage_return(response)
        headers['Content-Length'] = body.first.bytesize.to_s
      end

      [status, headers, body]
    end

    # Pads the response with the appropriate callback format according to the
    # JSON-P spec/requirements.
    #
    # The Rack response spec indicates that it should be enumerable. The
    # method of combining all of the data into a single string makes sense
    # since JSON is returned as a full string.
    #
    def pad(callback, response, body = "")
      response[2].each{ |s| body << s.to_s }
      close(response[2])
      if return_error?(response)
        error = MultiJson.encode({ :statusCode => response[0],
                                   :headers => response[1],
                                   :body => body })
        ["#{callback}(null, #{error})"]
      else
        ["#{callback}(#{body})"]
      end
    end

    def carriage_return(response, body = "")
      response[2].each{ |s| body << s.to_s }
      close(response[2])
      ["#{body}\n"]
    end

    # Close original response if it was Rack::BodyProxy (or anything else
    # responding to close, as we're going to lose it anyway), or it will cause
    # thread failures with newer Rack.
    def close(io)
      io.close if io.respond_to?(:close)
    end

    def return_error?(response)
      @return_errors && response[0] >= 400
    end
  end

end
