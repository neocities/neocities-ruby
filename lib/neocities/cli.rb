require 'pathname'
require 'pastel'
require 'tty/table'
require 'tty/prompt'
require_relative 'client'

module Neocities
  class CLI
    SUBCOMMANDS = %w{upload delete ls info}
    HELP_SUBCOMMANDS = ['-h', '--help', 'help']
    PENELOPE_MOUTHS = %w{^ o ~ - v U}
    PENELOPE_EYES = %w{o ~ O}

    def initialize(argv)
      @argv = argv.dup
      @pastel = Pastel.new eachline: "\n"
      @subcmd = @argv.first
      @subargs = @argv[1..@argv.length]
      @prompt = TTY::Prompt.new
    end

    def display_response(resp)
      if resp[:result] == 'success'
        puts "#{@pastel.green.bold 'SUCCESS:'} #{resp[:message]}"
      else
        out = "#{@pastel.red.bold 'ERROR:'} #{resp[:message]}"
        out += " (#{resp[:error_type]})" if resp[:error_type]
        puts out
      end
    end

    def run
      display_help_and_exit if @subcmd.nil? || @argv.include?(HELP_SUBCOMMANDS) || !SUBCOMMANDS.include?(@subcmd)

      if !@sitename && !@password
        @sitename = @prompt.ask('sitename:', default: ENV['NEOCITIES_SITENAME'])
        @password = @prompt.mask('password:', default: ENV['NEOCITIES_PASSWORD'])
        @client = Neocities::Client.new sitename: @sitename, password: @password
      end

      if @subcmd == 'info'
        resp = @client.info(@subargs[0] || @sitename)

        out = []

        resp[:info].each do |k,v|
          out.push [@pastel.bold(k), v]
        end

        puts TTY::Table.new(out).to_s
        exit
      end

      if @subcmd == 'ls'
        if @subargs.delete('--detail') == '--detail'
          @detail = true
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
              @pastel.green.bold(file[:path]),
              file[:size] || '',
              Time.parse(file[:updated_at]).localtime
            ])
          end
          puts TTY::Table.new(out).to_s
          exit
        end

        resp[:files].each do |file|
          puts file[:path]
        end
      end

      if @subcmd == 'delete'
        display_delete_help_and_exit if @subargs.empty?

        @subargs.each do |file|
          puts @pastel.bold("Deleting #{file} ...")
          resp = @client.delete file

          display_response resp
        end
      end

      if @subcmd == 'upload'
        display_upload_help_and_exit if @subargs.empty?

        @subargs.each do |path|
          path = Pathname path

          if !path.exist?
            display_response result: 'error', message: "#{path} does not exist locally."
            next
          end

          puts @pastel.bold("Uploading #{path} to /#{Pathname(path).basename} ...")
          resp = @client.upload path
          display_response resp
        end
      end
    end

    def display_delete_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'delete'} - Delete files on your Neocities site

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neo delete myfile.jpg'}                 Delete myfile.jpg

  #{@pastel.green '$ neo delete myfile.jpg myfile2.jpg'}     Delete myfile.jpg and myfile2.jpg

HERE
      exit
    end

    def display_upload_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.green.bold 'upload'} - Upload files to your Neocities site

  #{@pastel.dim 'Examples:'}

  #{@pastel.green '$ neo upload myfile.jpg'}                 Upload myfile.jpg

  #{@pastel.green '$ neo upload --dir images myfile.jpg'}    Upload myfile.jpg to the 'images' directory

  #{@pastel.green '$ neo upload .'}                          Upload all files and directories in current directory (#{Dir.getwd})

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
    upload          Upload files to your Neocities site.
    delete          Delete files from your Neocities site.
    ls #{@pastel.dim '[--detail]'}   List files from your Neocities site.
    info            Information and stats for your site

HERE
      exit
    end
  end
end
