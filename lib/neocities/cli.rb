require 'pathname'
require 'pastel'
require 'tty/table'
require 'tty/prompt'
require 'fileutils'
require 'json' # for reading configs
require 'whirly' # for loader spinner

require File.join(File.dirname(__FILE__), 'client')

module Neocities
  class CLI
    SUBCOMMANDS = %w{upload delete list info push logout pizza pull}
    HELP_SUBCOMMANDS = ['-h', '--help', 'help']
    PENELOPE_MOUTHS = %w{^ o ~ - v U}
    PENELOPE_EYES = %w{o ~ O}
    ALWAYS_EXCLUDED_PUSH_DIRECTORIES = %w{.git}.freeze

    def initialize(argv)
      @argv = argv.dup
      @pastel = Pastel.new eachline: "\n"
      @subcmd = @argv.first
      @subargs = @argv[1..@argv.length]
      @prompt = TTY::Prompt.new
      @api_key = ENV['NEOCITIES_API_KEY'] || nil
      @app_config_path = File.join self.class.app_config_path('neocities'), 'config.json' # added json extension
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
      display_sign_in_status if @argv.empty?

      if @argv[0] == 'version'
        puts Neocities::VERSION
        exit
      end

      if HELP_SUBCOMMANDS.include?(@subcmd) && SUBCOMMANDS.include?(@subargs[0])
        send "display_#{@subargs[0]}_help_and_exit"
      elsif @subcmd.nil? || !SUBCOMMANDS.include?(@subcmd)
        display_help_and_exit
      elsif @subargs.join("").match(HELP_SUBCOMMANDS.join('|')) && @subcmd != "info"
        send "display_#{@subcmd}_help_and_exit"
      end

      return logout if @subcmd == 'logout'

      if !@api_key
        begin
          file = File.read @app_config_path
          data = JSON.load file

          if data
            @api_key = data["API_KEY"]&.strip # Remove any trailing whitespace causing HTTP requests to fail
            @sitename = data["SITENAME"] # Store the sitename to be able to reference it later
            @last_pull = data["LAST_PULL"] # Store the last time a pull was performed so that we only fetch from updated files
          end
        rescue Errno::ENOENT
          @api_key = nil
        end
      end

      prompted_for_api_key = false
      if @api_key.nil? || @api_key.empty?
        puts 'Please enter your Neocities API key.'
        puts 'Create or copy one from https://neocities.org/settings'
        @api_key = @prompt.mask('API key:').to_s.strip
        prompted_for_api_key = true
      end

      @client = build_client @api_key

      if prompted_for_api_key || @sitename.nil?
        resp = @client.info
        if resp[:result] == 'error'
          display_response resp
          exit
        end

        @sitename = resp[:info][:sitename]
      end

      if prompted_for_api_key
        conf = {
          "API_KEY": @api_key,
          "SITENAME": @sitename,
        }

        FileUtils.mkdir_p Pathname(@app_config_path).dirname
        File.write @app_config_path, conf.to_json

        puts "The API key for #{@pastel.bold @sitename} has been stored in #{@pastel.bold @app_config_path}."
      end

      send @subcmd
    end

    def build_client(api_key)
      Neocities::Client.new api_key: api_key
    end

    def delete
      display_delete_help_and_exit if @subargs.empty?
      @subargs.each do |file|
        puts @pastel.bold("Deleting #{file} ...")
        resp = @client.delete file

        display_response resp
      end
    end

    def logout
      confirmed = false
      loop do
        case @subargs[0]
        when '-y' then @subargs.shift; confirmed = true
        when /^-/ then puts(@pastel.red.bold("Unknown option: #{@subargs[0].inspect}")); break
        else break
        end
      end
      if confirmed
        FileUtils.rm_f @app_config_path
        puts @pastel.bold("Your API key has been removed.")
      else
        display_logout_help_and_exit
      end
    end

    def info
      resp = @client.info(@subargs[0] || @sitename)

      if resp[:result] == 'error'
        display_response resp
        exit
      end

      out = []

      resp[:info].each do |k, v|
        v = Time.parse(v).localtime if v && (k == :created_at || k == :last_updated)
        out.push [@pastel.bold(k), v]
      end

      puts TTY::Table.new(out).to_s
      exit
    end

    def list
      display_list_help_and_exit if @subargs.empty?
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
      display_push_help_and_exit if @subargs.empty?
      @no_gitignore = false
      @excluded_files = []
      @dry_run = false
      @prune = false
      loop do
        case @subargs[0]
        when '--no-gitignore' then @subargs.shift; @no_gitignore = true
        when '-e' then @subargs.shift; @excluded_files.push(@subargs.shift)
        when '--dry-run' then @subargs.shift; @dry_run = true
        when '--prune' then @subargs.shift; @prune = true
        when /^-/ then puts(@pastel.red.bold("Unknown option: #{@subargs[0].inspect}")); display_push_help_and_exit
        else break
        end
      end

      if @subargs[0].nil?
        display_response result: 'error', message: "no local path provided"
        display_push_help_and_exit
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

      if @dry_run
        puts @pastel.green.bold("Doing a dry run, not actually pushing anything")
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
        paths.reject! { |path| always_excluded_push_path?(path) }

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

        paths.select! { |p| !@excluded_files.include?(p) }

        paths.select! { |p| !@excluded_files.include?(Pathname.new(p).dirname.to_s) }

        paths.collect! { |path| Pathname path }

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

      loop do
        case @subargs[0]
        when '-d' then @subargs.shift; @dir = @subargs.shift
        when /^-/ then puts(@pastel.red.bold("Unknown option: #{@subargs[0].inspect}")); display_upload_help_and_exit
        else break
        end
      end

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

    def pull
      begin
        quiet = (['--quiet', '-q'].include? @subargs[0])

        file = File.read @app_config_path
        data = JSON.load file

        last_pull_time = data["LAST_PULL"] ? data["LAST_PULL"]["time"] : nil
        last_pull_loc = data["LAST_PULL"] ? data["LAST_PULL"]["loc"] : nil

        Whirly.start spinner: ["😺", "😸", "😹", "😻", "😼", "😽", "🙀", "😿", "😾"], status: "Retrieving files for #{@pastel.bold @sitename}" if quiet
        resp = @client.pull @sitename, last_pull_time, last_pull_loc, quiet

        # write last pull data to file (not necessarily the best way to do this, but better than cloning every time)
        data["LAST_PULL"] = {
          "time": Time.now,
          "loc": Dir.pwd
        }

        File.write @app_config_path, data.to_json
      rescue StandardError => ex
        Whirly.stop if quiet
        puts @pastel.red.bold "\nA fatal error occurred :-("
        puts @pastel.red ex
      ensure
        exit
      end
    end

    def pizza
      display_pizza_help_and_exit
    end

    def display_pizza_help_and_exit
      excuses = [
        "Sorry, we're fresh out of pineapple today.",
        "All the toppings just went rogue and are currently answering to no god.",
        "Our bicycle delivery guy is out today for ska band practice.",
        "Doughpocalypse now. Pizza's off until further notice.",
        "Mamma mia! We're outta the cheesa.",
        "The sauce of our youth ran dry. Pizza is off the menu for now.",
        "There was this pizza place in Portland called Lonesomes that taped burned CDs of local bands to the pizza box. It was pretty dope.",
        "No dough, no go, sorry joe.",
        "I'll be right with you after I figure out how to center a div in CSS.",
        "The pizza gods demand rest. Are the hunger pangs interrupting your game?",
        "Our pizza chef currently has the high score on the Road Kings pinball machine, you dare disturb him?",
        "Today's special: disappointment. Pizza unavailable.",
        "Our last pizza became a perpetual motion machine, left the atmosphere and is flying through the heavens.",
        "Ran out of oregano and optimism. See you next time.",
        "WAR AND PEACE, BY LEO TOLSTOY, BOOK ONE: 1805, CHAPTER I  “Well, Prince, so Genoa and Lucca are now just family estates of the Buonapartes. But I warn you, if you don’t tell me that this means war, if you still try to defend the infamies and horrors perpetrated by that Antichrist—I really believe he is Antichrist—I will have nothing more to do with you and you are no longer my friend, no longer my ‘faithful slave,’ as you call yourself! But how do you do? I see I have frightened you—sit down and tell me all the news.”

It was in July, 1805, and the speaker was the well-known Anna Pávlovna Schérer, maid of honor and favorite of the Empress Márya Fëdorovna. With these words she greeted Prince Vasíli Kurágin, a man of high rank and importance, who was the first to arrive at her reception. Anna Pávlovna had had a cough for some days. She was, as she said, suffering from la grippe; grippe being then a new word in St. Petersburg, used only by the elite.

All her invitations without exception, written in French, and delivered by a scarlet-liveried footman that morning, ran as follows:

“If you have nothing better to do, Count (or Prince), and if the prospect of spending an evening with a poor invalid is not too terrible, I shall be very charmed to see you tonight between 7 and 10—Annette Schérer.”

“Heavens! what a virulent attack!” replied the prince, not in the least disconcerted by this reception. He had just entered, wearing an embroidered court uniform, knee breeches, and shoes, and had stars on his breast and a serene expression on his flat face. He spoke in that refined French in which our grandfathers not only spoke but thought, and with the gentle, patronizing intonation natural to a man of importance who had grown old in society and at court. He went up to Anna Pávlovna, kissed her hand, presenting to her his bald, scented, and shining head, and complacently seated himself on the sofa.

“First of all, dear friend, tell me how you are. Set your friend’s mind at rest,” said he without altering his tone, beneath the politeness and affected sympathy of which indifference and even irony could be discerned.

“Can one be well while suffering morally? Can one be calm in times like these if one has any feeling?” said Anna Pávlovna. “You are staying the whole evening, I hope?”

“And the fete at the English ambassador’s? Today is Wednesday. I must put in an appearance there,” said the prince. “My daughter is coming for me to take me there.”

“I thought today’s fete had been canceled. I confess all these festivities and fireworks are becoming wearisome.”

“If they had known that you wished it, the entertainment would have been put off,” said the prince, who, like a wound-up clock, by force of habit said things he did not even wish to be believed.

“Don’t tease! Well, and what has been decided about Novosíltsev’s dispatch? You know everything.”

“What can one say about it?” replied the prince in a cold, listless tone. “What has been decided? They have decided that Buonaparte has burnt his boats, and I believe that we are ready to burn ours.”

Prince Vasíli always spoke languidly, like an actor repeating a stale part. Anna Pávlovna Schérer on the contrary, despite her forty years, overflowed with animation and impulsiveness. To be an enthusiast had become her social vocation and, sometimes even when she did not feel like it, she became enthusiastic in order not to disappoint the expectations of those who knew her. The subdued smile which, though it did not suit her faded features, always played round her lips expressed, as in a spoiled child, a continual consciousness of her charming defect, which she neither wished, nor could, nor considered it necessary, to correct.

In the midst of a conversation on political matters Anna Pávlovna burst out:

“Oh, don’t speak to me of Austria. Perhaps I don’t understand things, but Austria never has wished, and does not wish, for war. She is betraying us! Russia alone must save Europe. Our gracious sovereign recognizes his high vocation and will be true to it. That is the one thing I have faith in! Our good and wonderful sovereign has to perform the noblest role on earth, and he is so virtuous and noble that God will not forsake him. He will fulfill his vocation and crush the hydra of revolution, which has become more terrible than ever in the person of this murderer and villain! We alone must avenge the blood of the just one.... Whom, I ask you, can we rely on?... England with her commercial spirit will not and cannot understand the Emperor Alexander’s loftiness of soul. She has refused to evacuate Malta. She wanted to find, and still seeks, some secret motive in our actions. What answer did Novosíltsev get? None. The English have not understood and cannot understand the self-abnegation of our Emperor who wants nothing for himself, but only desires the good of mankind. And what have they promised? Nothing! And what little they have promised they will not perform! Prussia has always declared that Buonaparte is invincible, and that all Europe is powerless before him.... And I don’t believe a word that Hardenburg says, or Haugwitz either. This famous Prussian neutrality is just a trap. I have faith only in God and the lofty destiny of our adored monarch. He will save Europe!”

She suddenly paused, smiling at her own impetuosity.

“I think,” said the prince with a smile, “that if you had been sent instead of our dear Wintzingerode you would have captured the King of Prussia’s consent by assault. You are so eloquent. Will you give me a cup of tea?”

“In a moment. À propos,” she added, becoming calm again, “I am expecting two very interesting men tonight, le Vicomte de Mortemart, who is connected with the Montmorencys through the Rohans, one of the best French families. He is one of the genuine émigrés, the good ones. And also the Abbé Morio. Do you know that profound thinker? He has been received by the Emperor. Had you heard?”

“I shall be delighted to meet them,” said the prince. “But tell me,” he added with studied carelessness as if it had only just occurred to him, though the question he was about to ask was the chief motive of his visit, “is it true that the Dowager Empress wants Baron Funke to be appointed first secretary at Vienna? The baron by all accounts is a poor creature.”

Prince Vasíli wished to obtain this post for his son, but others were trying through the Dowager Empress Márya Fëdorovna to secure it for the baron.

Anna Pávlovna almost closed her eyes to indicate that neither she nor anyone else had a right to criticize what the Empress desired or was pleased with.

“Baron Funke has been recommended to the Dowager Empress by her sister,” was all she said, in a dry and mournful tone.

As she named the Empress, Anna Pávlovna’s face suddenly assumed an expression of profound and sincere devotion and respect mingled with sadness, and this occurred every time she mentioned her illustrious patroness. She added that Her Majesty had deigned to show Baron Funke beaucoup d’estime, and again her face clouded over with sadness.

The prince was silent and looked indifferent. But, with the womanly and courtierlike quickness and tact habitual to her, Anna Pávlovna wished both to rebuke him (for daring to speak as he had done of a man recommended to the Empress) and at the same time to console him, so she said:

“Now about your family. Do you know that since your daughter came out everyone has been enraptured by her? They say she is amazingly beautiful.”

The prince bowed to signify his respect and gratitude.

“I often think,” she continued after a short pause, drawing nearer to the prince and smiling amiably at him as if to show that political and social topics were ended and the time had come for intimate conversation—“I often think how unfairly sometimes the joys of life are distributed. Why has fate given you two such splendid children? I don’t speak of Anatole, your youngest. I don’t like him,” she added in a tone admitting of no rejoinder and raising her eyebrows. “Two such charming children. And really you appreciate them less than anyone, and so you don’t deserve to have them.”

And she smiled her ecstatic smile.

“I can’t help it,” said the prince. “Lavater would have said I lack the bump of paternity.”

“Don’t joke; I mean to have a serious talk with you. Do you know I am dissatisfied with your younger son? Between ourselves” (and her face assumed its melancholy expression), “he was mentioned at Her Majesty’s and you were pitied....”

The prince answered nothing, but she looked at him significantly, awaiting a reply. He frowned."
      ]
      puts @pastel.bright_red(excuses.sample)
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

    def display_pull_help_and_exit
      display_banner

      puts <<HERE
  #{@pastel.magenta.bold 'pull'} - Get the most recent version of files from your site, does not download if files haven't changed

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

    def display_sign_in_status
      config = {}
      begin
        config = JSON.parse File.read(@app_config_path)
      rescue SystemCallError, JSON::ParserError
        # Status should still be available without a readable config.
      end
      config = {} unless config.is_a?(Hash)
      saved_key = config['API_KEY'].to_s.strip
      environment_key = ENV['NEOCITIES_API_KEY']

      status = if environment_key && environment_key != saved_key
        environment_key.empty? ? 'Signed out' : 'Using NEOCITIES_API_KEY (username not loaded)'
      elsif saved_key.empty?
        'Signed out'
      elsif config['SITENAME'].to_s.empty?
        'API key saved (username not loaded)'
      else
        "Signed in as: #{config['SITENAME']}"
      end
      puts @pastel.cyan.bold(status)
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
    pull        Get the most recent version of files from your site
    pizza       Order a free pizza

  The first command asks for an API key from your site settings.
  Set NEOCITIES_API_KEY to use a key without saving it locally.

HERE
      exit
    end

    def always_excluded_push_path?(path)
      Pathname.new(path).each_filename.any? do |filename|
        ALWAYS_EXCLUDED_PUSH_DIRECTORIES.include?(filename)
      end
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
