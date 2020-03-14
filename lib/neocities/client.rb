begin
  require 'openssl/win/root' if Gem.win_platform?
rescue
end

require 'json'
require 'pathname'
require 'uri'
require 'digest'
require 'httpclient'

module Neocities
  class Client
    API_URI = 'https://neocities.org/api/'

    def initialize(opts={})
      @uri = URI.parse API_URI
      @http = HTTPClient.new force_basic_auth: true
      @opts = opts

      unless opts[:api_key] || (opts[:sitename] && opts[:password])
        raise ArgumentError, 'client requires a login (sitename/password) or an api_key'
      end

      if opts[:api_key]
        @http.default_header = {'Authorization' => "Bearer #{opts[:api_key]}"}
      else
        @http.set_auth API_URI, opts[:sitename], opts[:password]
      end

    end

    def list(path=nil)
      get 'list', :path => path
    end

    def key
      get 'key'
    end

    def upload_hash(remote_path, sha1_hash)
      post 'upload_hash', remote_path => sha1_hash
    end

    def upload(path, remote_path=nil, dry_run=false)
      path = Pathname path

      unless path.exist?
        raise ArgumentError, "#{path.to_s} does not exist."
      end

      rpath = (remote_path || path.basename)

      res = upload_hash rpath, Digest::SHA1.file(path.to_s).hexdigest

      if res[:files] && res[:files][remote_path.to_s.to_sym] == true
        return {result: 'error', error_type: 'file_exists', message: 'file already exists and matches local file, not uploading'}
      else
        if dry_run
          return {result: 'success'}
        else
          File.open(path.to_s) do |file|
            post 'upload', rpath => file
          end
        end
      end
    end

    def delete_wrapper_with_dry_run(paths, dry_run=false)
      if dry_run
        return {result: 'success'}
      else
        delete(paths)
      end
    end

    def delete(*paths)
      post 'delete', 'filenames[]' => paths
    end

    def info(sitename)
      get 'info', sitename: sitename
    end

    def get(path, params={})
      uri = @uri+path
      uri.query = URI.encode_www_form params
      resp = @http.get uri
      JSON.parse resp.body, symbolize_names: true
    end

    def post(path, args={})
      uri = @uri+path
      resp = @http.post uri, args
      JSON.parse resp.body, symbolize_names: true
    end
  end
end
