require 'net/http'
require 'net/https'
require 'json'
require 'pathname'
require 'uri'
require 'net/http/post/multipart'

module Neocities
  class Client
    API_URI = 'https://neocities.org/api/'

    def initialize(opts={})
      @uri = URI.parse API_URI
      @http = Net::HTTP.new @uri.host, @uri.port
      @http.use_ssl = true
      @opts = opts

      unless @opts[:api_key] || (@opts[:sitename] && @opts[:password])
        raise ArgumentError, 'client requires a login (sitename/password) or an api_key'
      end
    end

    def list(path=nil)
      get 'list', :path => path
    end

    def key
      get 'key'
    end

    def upload(path, remote_path=nil)
      path = Pathname path

      unless path.exist?
        raise ArgumentError, "#{path.to_s} does not exist."
      end

      post 'upload', (remote_path || path.basename) => UploadIO.new(path.to_s, 'application/octet-stream')
    end

    def delete(*paths)
      post 'delete', 'filenames[]' => paths
    end

    def info(sitename)
      get 'info', sitename: sitename
    end

    private

    def get(path, params={})
      req = Net::HTTP::Get.new "#{@uri.path}#{path}?#{URI.encode_www_form(params)}"
      request req
    end

    def post(path, args={})
      req = Net::HTTP::Post::Multipart.new("#{@uri.path}#{path}", args)
      res = request req
    end

    def request(req)
      if @opts[:api_key]
        req['Authorization'] = "Bearer #{@opts[:api_key]}"
      else
        req.basic_auth @opts[:sitename], @opts[:password]
      end
      resp = @http.request req
      JSON.parse resp.body, symbolize_names: true
    end
  end
end
