require 'pathname'
require 'pastel'
require 'tty/table'
require 'tty/prompt'
require 'fileutils'
require File.join(File.dirname(__FILE__), 'client')

module Neocities
  class CLI
    SUBCOMMANDS = %w{upload delete list info push logout pizza}
    HELP_SUBCOMMANDS = ['-h', '--help', 'help']
    PENELOPE_MOUTHS = %w{^ o ~ - v U}
    PENELOPE_EYES = %w{o ~ O}

    def initialize(argv)
      @argv = argv.dup
      @pastel = Pastel.new eachline: "\n"
      @subcmd = @argv.first
      @subargs = @argv[1..@argv.length]
      @prompt = TTY::Prompt.new
      @api_key = ENV['NEOCITIES_API_KEY'] || nil
      @app_config_path = File.join self.class.app_config_path('neocities'), 'config'
    end

    def display_response(resp)
      if resp[:result] == 'success'
        puts "#{@pastel.green.bold 'SUCCESS:'} #{resp[:message]}"
      elsif resp[:result] == 'error' && resp[:error_type] == 'file_exists'
        out = "#{@pastel.yellow.bold 'EXISTS:'} #{resp[:message]}"
        out += " (#{resp[:error_type]})" if resp[:error_type]
        puts out
      else
        out = "#{@pastel.red.bold 'ERROR:'} #{resp[:message]}"
        out += " (#{resp[:error_type]})" if resp[:error_type]
        puts out
      end
    end

    def run
      if @argv[0] == 'version'
        puts Neocities::VERSION
        exit
      end

      display_help_and_exit if @subcmd.nil? || @argv.include?(HELP_SUBCOMMANDS) || !SUBCOMMANDS.include?(@subcmd)
      send "display_#{@subcmd}_help_and_exit" if @subargs.empty?

      if !@api_key
        begin
          @api_key = File.read @app_config_path
          # Remove any trailing whitespace causing HTTP requests to fail
          @api_key = @api_key.strip
        rescue Errno::ENOENT
          @api_key = nil
        end
      end 

      if @api_key.nil?
        puts "Please login to get your API key:"

        if !@sitename && !@password
          @sitename = @prompt.ask('sitename:', default: ENV['NEOCITIES_SITENAME'])
          @password = @prompt.mask('password:', default: ENV['NEOCITIES_PASSWORD'])
        end

        @client = Neocities::Client.new sitename: @sitename, password: @password

        resp = @client.key
        if resp[:api_key]
          FileUtils.mkdir_p Pathname(@app_config_path).dirname
          File.write @app_config_path, resp[:api_key]
          puts "The api key for #{@pastel.bold @sitename} has been stored in #{@pastel.bold @app_config_path}."
        else
          display_response resp
          exit
        end
      else
        @client = Neocities::Client.new api_key: @api_key
      end

      send @subcmd
    end

    def delete
      @subargs.each do |file|
        puts @pastel.bold("Deleting #{file} ...")
        resp = @client.delete file

        display_response resp
      end
    end

    def logout
      confirmed = false
      loop {
        case @subargs[0]
        when '-y' then @subargs.shift; confirmed = true
        when /^-/ then puts(@pastel.red.bold("Unknown option: #{@subargs[0].inspect}")); display_logout_help_and_exit
        else break
        end
      }
      if confirmed
        FileUtils.rm @app_config_path
        puts @pastel.bold("Your api key has been removed.")
      end
    end

    def info
      resp = @client.info(@subargs[0] || @sitename)

      if resp[:result] == 'error'
        display_response resp
        exit
      end

      out = []

      resp[:info].each do |k,v|
        v = Time.parse(v).localtime if v && (k == :created_at || k == :last_updated)
        out.push [@pastel.bold(k), v]
      end

      puts TTY::Table.new(out).to_s
      exit
    end

    def list
      if @subargs.delete('-d') == '-d'
        @detail = true
      end

      if @subargs.delete('-a')
        @subargs[0] = nil
      end

      resp = @client.list @subargs[0]

      if resp[:result] == 'error'
        display_response resp
        exit
      end

      if @detail
        out = [
          [@pastel.bold('Path'), @pastel.bold('Size'), @pastel.bold('Updated')]
        ]
        resp[:files].each do |file|
          out.push([
            @pastel.send(file[:is_directory] ? :blue : :green).bold(file[:path]),
            file[:size] || '',
            Time.parse(file[:updated_at]).localtime
          ])
        end
        puts TTY::Table.new(out).to_s
        exit
      end

      resp[:files].each do |file|
        puts @pastel.send(file[:is_directory] ? :blue : :green).bold(file[:path])
      end
    end

    def push
      @no_gitignore = false
      @excluded_files = []
      @dry_run = false
      @prune = false
      loop {
        case @subargs[0]
        when '--no-gitignore' then @subargs.shift; @no_gitignore = true
        when '-e' then @subargs.shift; @excluded_files.push(@subargs.shift)
        when '--dry-run' then @subargs.shift; @dry_run = true
        when '--prune' then @subargs.shift; @prune = true
        when /^-/ then puts(@pastel.red.bold("Unknown option: #{@subargs[0].inspect}")); display_push_help_and_exit
        else break
        end
      }

      if @dry_run
        puts @pastel.green.bold("Doing a dry run, not actually pushing anything")
      end

      root_path = Pathname @subargs[0]

      if !root_path.exist?
        display_response result: 'error', message: "path #{root_path} does not exist"
        display_push_help_and_exit
      end

      if !root_path.directory?
        display_response result: 'error', message: 'provided path is not a directory'
        display_push_help_and_exit
      end

      if @prune
        pruned_dirs = []
        resp = @client.list
        resp[:files].each do |file|
          path = Pathname(File.join(@subargs[0], file[:path]))

          pruned_dirs << path if !path.exist? && (file[:is_directory])

          if !path.exist? && !pruned_dirs.include?(path.dirname)
            print @pastel.bold("Deleting #{file[:path]} ... ")
            resp = @client.delete_wrapper_with_dry_run file[:path], @dry_run

            if resp[:result] == 'success'
              print @pastel.green.bold("SUCCESS") + "\n"
            else
              print "\n"
              display_response resp
            end
          end
        end
      end

      Dir.chdir(root_path) do
        paths = Dir.glob(File.join('**', '*'), File::FNM_DOTMATCH)

        if @no_gitignore == false
          begin
            ignores = File.readlines('.gitignore').collect! do |ignore|
              ignore.strip!
              File.directory?(ignore) ? "#{ignore}**" : ignore
            end
            paths.select! do |path|
              res = true
              ignores.each do |ignore|
                if File.fnmatch?(ignore.strip, path)
                  res = false
                  break
                end
              end
            end
            puts "Not pushing .gitignore entries (--no-gitignore to disable)"
          rescue Errno::ENOENT
          end
        end

        paths.select! {|p| !@excluded_files.include?(p)}

        paths.select! {|p|
          !@excluded_files.include?(Pathname.new(p).dirname.to_s)
        }

        paths.collect! {|path| Pathname path}

        paths.each do |path|
          next if path.directory?
          print @pastel.bold("Uploading #{path} ... ")
          resp = @client.upload path, path, @dry_run

          if resp[:result] == 'error' && resp[:error_type] == 'file_exists'
            print @pastel.yellow.bold("EXISTS") + "\n"
          elsif resp[:result] == 'success'
            print @pastel.green.bold("SUCCESS") + "\n"
          else
            print "\n"
            display_response resp
          end
        end
      end
    end

    def upload
      display_upload_help_and_exit if @subargs.empty?
      @dir = ''

      loop {
        case @subargs[0]
        when '-d' then @subargs.shift; @dir = @subargs.shift
        when /^-/ then puts(@pastel.red.bold("Unknown option: #{@subargs[0].inspect}")); display_upload_help_and_exit
        else break
        end
      }

      @subargs.each do |path|
        path = Pathname path

        if !path.exist?
          display_response result: 'error', message: "#{path} does not exist locally."
          next
        end

        if path.directory?
          puts "#{path} is a directory, skipping (see the push command)"
          next
        end

        remote_path = ['/', @dir, path.basename.to_s].join('/').gsub %r{/+}, '/'

        puts @pastel.bold("Uploading #{path} to #{remote_path} ...")
        resp = @client.upload path, remote_path
        display_response resp
      end
    end

    def display_pizza_help_and_exit
      puts "Sorry, we're fresh out of dough today. Try again tomorrow."
      exit
    end

    def display_list_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'list'} - List files on your Neocities site

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neocities list /'}           List files in your root directory

  #{@pastel.green '$ neocities list -a'}          Recursively display all files and directories

  #{@pastel.green '$ neocities list -d /mydir'}   Show detailed information on /mydir

HERE
      exit
    end

    def display_delete_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'delete'} - Delete files on your Neocities site

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neocities delete myfile.jpg'}               Delete myfile.jpg

  #{@pastel.green '$ neocities delete myfile.jpg myfile2.jpg'}   Delete myfile.jpg and myfile2.jpg

  #{@pastel.green '$ neocities delete mydir'}                    Deletes mydir and everything inside it (be careful!)

HERE
      exit
    end

    def display_upload_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'upload'} - Upload individual files to your Neocities site

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neocities upload img.jpg img2.jpg'}    Upload images to the root of your site

  #{@pastel.green '$ neocities upload -d images img.jpg'}   Upload img.jpg to the 'images' directory on your site

HERE
      exit
    end

    def display_push_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'push'} - Recursively upload a local directory to your Neocities site

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neocities push .'}                                 Recursively upload current directory.

  #{@pastel.green '$ neocities push -e node_modules -e secret.txt .'}   Exclude certain files from push

  #{@pastel.green '$ neocities push --no-gitignore .'}                  Don't use .gitignore to exclude files

  #{@pastel.green '$ neocities push --dry-run .'}                       Just show what would be uploaded
      
  #{@pastel.green '$ neocities push --prune .'}                         Delete site files not in dir (be careful!)

HERE
      exit
    end

    def display_info_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'info'} - Get site info

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neocities info fauux'}   Gets info for 'fauux' site

HERE
      exit
    end

    def display_logout_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'logout'} - Remove the site api key from the config

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neocities logout -y'}

HERE
      exit
    end

    def display_banner
      puts <<HERE

  |\\---/|
  | #{PENELOPE_EYES.sample}_#{PENELOPE_EYES.sample} |  #{@pastel.on_cyan.bold ' Neocities '}
   \\_#{PENELOPE_MOUTHS.sample}_/

HERE
    end

    def display_help_and_exit
      display_banner
      puts <<HERE
  #{@pastel.dim 'Subcommands:'}
    push        Recursively upload a local directory to your site
    upload      Upload individual files to your Neocities site
    delete      Delete files from your Neocities site
    list        List files from your Neocities site
    info        Information and stats for your site
    logout      Remove the site api key from the config
    version     Unceremoniously display version and self destruct
    pizza       Order a free pizza

HERE
      exit
    end

    def self.app_config_path(name)
      platform = if RUBY_PLATFORM =~ /win32/
        :win32
      elsif RUBY_PLATFORM =~ /darwin/
        :darwin
      elsif RUBY_PLATFORM =~ /linux/
        :linux
      else
        :unknown
      end

      case platform
      when :linux
        if ENV['XDG_CONFIG_HOME']
          return File.join(ENV['XDG_CONFIG_HOME'], name)
        end

        if ENV['HOME']
          return File.join(ENV['HOME'], '.config', name)
        end
      when :darwin
        return File.join(ENV['HOME'], 'Library', 'Application Support', name)
      else
        # Windows platform detection is weird, just look for the env variables
        if ENV['LOCALAPPDATA']
          return File.join(ENV['LOCALAPPDATA'], name)
        end

        if ENV['USERPROFILE']
          return File.join(ENV['USERPROFILE'], 'Local Settings', 'Application Data', name)
        end

        # Should work for the BSDs
        if ENV['HOME']
          return File.join(ENV['HOME'], '.'+name)
        end
      end
    end
  end
end
