begin
  require 'openssl/win/root' if Gem.win_platform?
rescue
end

require 'json'
require 'pathname'
require 'uri'
require 'digest'
require 'http'
require 'pastel'
require 'date'
require 'whirly'

module Neocities
  class Client
    API_URI = 'https://neocities.org/api/'

    def initialize(opts={})
      @uri = URI.parse API_URI
      @opts = opts
      @pastel = Pastel.new eachline: "\n"

      unless opts[:api_key] || (opts[:sitename] && opts[:password])
        raise ArgumentError, 'client requires a login (sitename/password) or an api_key'
      end

      if opts[:api_key]
        @http = HTTP.auth("Bearer #{opts[:api_key]}")
      else
        @http = HTTP.basic_auth user: opts[:sitename], pass: opts[:password]
      end
    end

    def list(path=nil)
      get 'list', :path => path
    end

    def pull(sitename, last_pull_time=nil, last_pull_loc=nil, quiet=true)
      site_info = get 'info', sitename: sitename

      if site_info[:result] == 'error'
        raise ArgumentError, site_info[:message]
      end

      # handle custom domains for supporter accounts
      if site_info[:info][:domain] && site_info[:info][:domain] != ""
        domain = "https://#{site_info[:info][:domain]}/"
      else
        domain = "https://#{sitename}.neocities.org/"
      end

      # start stats
      success_loaded = 0
      start_time = Time.now
      curr_dir = Dir.pwd

      # get list of files
      resp = get 'list'

      if resp[:result] == 'error'
        raise ArgumentError, resp[:message]
      end
      
      # fetch each file
      uri_parser = URI::Parser.new
      resp[:files].each do |file|
        if !file[:is_directory]
          print @pastel.bold("Pulling #{file[:path]} ... ") if !quiet
          
          if 
            last_pull_time && \
            last_pull_loc && \
            Time.parse(file[:updated_at]) <= Time.parse(last_pull_time) && \
            last_pull_loc == curr_dir && \
            File.exist?(file[:path]) # case when user deletes file
            # case when file hasn't been updated since last 
            print "#{@pastel.yellow.bold "NO NEW UPDATES"}\n" if !quiet
            next
          end
          
          pathtotry = uri_parser.escape(domain + file[:path])
          fileconts = @http.follow.get pathtotry

          if fileconts.status == 200
            print "#{@pastel.green.bold 'SUCCESS'}\n" if !quiet
            success_loaded += 1

            File.open("#{file[:path]}", "w") do |f|
              f.write(fileconts.body)
            end
          else
            print "#{@pastel.red.bold 'FAIL'}\n" if !quiet
          end
        else
          FileUtils.mkdir_p "#{file[:path]}"
        end
      end

      # calculate time command took
      total_time = Time.now - start_time

      # stop the spinner, if there is one
      Whirly.stop if quiet

      # display stats
      puts @pastel.green "\nSuccessfully fetched #{success_loaded} files in #{total_time.round(2)} seconds"
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

      res = upload_hash rpath.to_s, Digest::SHA1.file(path.to_s).hexdigest

      if res[:files] && res[:files][remote_path.to_s.to_sym] == true
        return {result: 'error', error_type: 'file_exists', message: 'file already exists and matches local file, not uploading'}
      else
        if dry_run
          return {result: 'success'}
        else
          File.open(path.to_s) do |file|
            post 'upload', rpath => HTTP::FormData::File.new(file)
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
      resp = @http.post uri, form: args
      JSON.parse resp.body, symbolize_names: true
    end
  end
end