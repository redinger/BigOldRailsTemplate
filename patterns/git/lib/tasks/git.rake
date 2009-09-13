# Rake tasks for managing git plugins with submodules.
#
# These tasks aim to make life simpler by automating all the boring work.
# What you get:
#   - complete git integration (all you need to know is install, uninstall and update)
#   - complete github integration (only use author name + plugin name)
#   - rails plugin hooks (install.rb/uninstall.rb) are taken care of 
#
# Available commands:
# 
# rake git:submodules:init
#   You don't have to run this, but someone cloning your repo does
# 
# rake git:plugin:install maxim-shmacros
#   Install github.com/maxim/shmacros plugin (you can also use / (ie maxim/shmacros))
#   
# rake git:plugin:uninstall shmacros
#   Uninstall shmacros plugin (no author name this time)
#
# rake git:plugin:update shmacros
#   Update shmacros plugin
#
# rake git:plugins:update
#   Update all plugins (notice plural plugins, this is to prevent accidents)
#
# rake git:plugins:list
#   List all plugins and their commit hashes


namespace :git do
  namespace :submodules do
    desc "Initialize git submodules"
    task :init do
      system "git submodule init"
      system "git submodule update"
    end
  end
  
  namespace :plugin do
    desc "Install rails plugin as git submodule"
    task :install do
      arg = ARGV[1].strip
      if arg =~ /^git:\/\//
        url_parts = arg.scan(/\/([^\/]+)/).flatten
        user_nick = url_parts[1]
        plugin_name = url_parts[2].split('.').first
      else
        user_nick, plugin_name = ARGV[1].split(/[\/-]/, 2).map(&:strip)
      end
      
      if [user_nick, plugin_name].any?(&:nil?)
        puts "Plugin path is invalid."
        exit(0)
      end
      
      origin = "git://github.com/#{user_nick}/#{plugin_name}.git"
      destination = "vendor/plugins/#{plugin_name}"
      (puts "Plugin #{plugin_name} is already installed."; exit(0)) if File.exist?(destination)
      puts "Installing #{origin} into #{destination}."
      system "git submodule add #{origin} #{destination}"
      installed = plugin_installed?(plugin_name)
      
      if installed && File.exist?(install_hook = "#{destination}/install.rb")
        puts "Running #{install_hook}..."
        Rake::Task[:environment].invoke
        load install_hook
      end
      
      if !installed
        puts "Installation failed."
        exit(0)
      end
      
      Rake::Task['git:submodules:init'].invoke
      
      puts "Plugin #{plugin_name} is successfully installed."
      exit(0)
    end
    
    desc "Uninstall submodule'd plugin"
    task :uninstall do
      plugin_name = ARGV[1].strip
      (puts "Plugin #{plugin_name} not found."; exit(0)) unless plugin_installed?(plugin_name)
      
      submodule = plugins_list.find{|p| p[:name] == plugin_name}
      
      if File.exist?(uninstall_hook = "#{submodule[:path]}/uninstall.rb")
        puts "Running #{uninstall_hook}..."
        Rake::Task[:environment].invoke
        load uninstall_hook
      end
      
      lines = File.readlines(".gitmodules")
      lines_count = 0
      goner_lines = []
      lines.each_slice(3) do |declaration|
        if declaration[0].include?(submodule[:path]) &&
            declaration[1].include?(submodule[:path]) &&
            declaration[2].include?(submodule[:url])
          goner_lines += [lines_count, lines_count+1, lines_count+2]
        end
        lines_count += 3
      end
      
      goner_lines.each{|num| lines[num] = nil}
      lines.compact!
      
      File.open(".gitmodules", "w") do |gitmodule|
        gitmodule.write(lines.join)
      end
      puts "Removed declaration from .gitmodules."

      lines = File.readlines(".git/config")
      lines_count = 0
      goner_lines = []
      lines.each_cons(2) do |pair|
        if pair.first.include?(submodule[:path]) && pair.last.include?(submodule[:url])
          goner_lines += [lines_count, lines_count+1]
        end
        lines_count += 1
      end

      goner_lines.each{|num| lines[num] = nil}
      lines.compact!
      
      File.open(".git/config", "w") do |config_file|
        config_file.write(lines.join)
      end
      puts "Removed declaration from .git/config."
      
      system "git rm --cached #{submodule[:path]}"
      system "rm -rf #{submodule[:path]}"
      system "git add .gitmodules"
      puts "Done!"
      exit(0)
    end
    
    desc "Update a plugin"
    task :update => "git:submodules:init" do
      plugin_name = ARGV[1].strip
      (puts "Plugin #{plugin_name} not found."; exit(0)) unless plugin_installed?(plugin_name)

      submodule = plugins_list.find{|p| p[:name] == plugin_name}
      puts "Updating #{submodule[:name]}..."
      system "cd #{submodule[:path]} && git checkout master && git pull && cd ../.."
      puts "Done!"
      exit(0)
    end
  end
  
  namespace :plugins do
    desc "List all submodule'd plugins"
    task :list do
      puts "\n"
      plugins_list.each do |plugin|
        puts plugin[:name]
        plugin.each_pair do |key, value|
          puts "  #{key}: #{value}" unless key == :name
        end
        puts "\n"
      end
    end
    
    desc "Update all plugins"
    task :update do
      plugins_list.each do |plugin|
        system "rake git:plugin:update #{plugin[:name]}"
      end
    end
  end
  
  def plugins_list
    gitmodules_file = read_gitmodules_or_fail
    lines = gitmodules_file.split("\n")
    submodules = []
    lines.each_slice(3) do |declaration|
      next if declaration[1] =~ /vendor\/rails/
      submodule = {
        :path => (path = declaration[1].split('=')[1].strip),
        :name => path.split('/').last,
        :url => declaration[2].split('=')[1].strip,
        :hash => File.read(path + "/.git/" + File.read("#{path}/.git/HEAD").split(':')[1].strip).strip
      }
      submodules << submodule
    end
    
    submodules
  end
  
  def read_gitmodules_or_fail
    if !File.exist?('.gitmodules') || 
      (gitmodules_file = File.read('.gitmodules').strip).empty? ||
      (gitmodules_file.split("\n").size < 6 && gitmodules_file =~ /vendor\/rails/)
      puts "No plugins found."
      exit(0)
    end
    gitmodules_file
  end
  
  def plugin_installed?(name)
    plugins_list.find{|p| p[:name] == name}
  end
end