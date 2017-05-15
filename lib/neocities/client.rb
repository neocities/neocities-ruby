require 'http'
require 'json'
require 'pathname'

module Neocities
  class Client
    API_URI = 'https://neocities.org/api/'

    def initialize(opts={})
      if opts[:api_key]
        @http = HTTP.auth "Bearer #{opts[:api_key]}"
      elsif opts[:sitename] && opts[:password]
        @http = HTTP.basic_auth user: opts[:sitename], pass: opts[:password]
      else
        raise ArgumentError, 'client requires a login (sitename/password) or an api_key'
      end
    end

    def list(path=nil)
      run :get, 'list', params: {path: path}
    end

    def key
      run :get, 'key', {}
    end

    def upload(path, remote_path=nil)
      path = Pathname path

      unless path.exist?
        raise ArgumentError, "#{path.to_s} does not exist."
      end

      run :post, 'upload', form: {
        (remote_path || path.basename) => HTTP::FormData::File.new(path.to_s)
      }
    end

    def delete(*paths)
      run :post, 'delete', form: {'filenames[]' => paths}
    end

    def info(sitename)
      run :get, 'info', params: {sitename: sitename}
    end

    private

    def run(meth, path, args)
      resp = @http.send(meth, API_URI+path, args)
      JSON.parse resp.body, symbolize_names: true
    end

  end
end
