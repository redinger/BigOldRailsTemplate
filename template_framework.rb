require 'open-uri'
require 'yaml'

module Rails
  class TemplateRunner

# Logging
    # Turn on for noisy logging during template generation
    DEBUG_LOGGING = false

    def debug_log(msg)
      if DEBUG_LOGGING
        log msg
      end
    end

# Accessors and Initialization
    def current_app_name
      current_app_name = File.basename(File.expand_path(root))
    end

    # TODO: This list should be data driven
    attr_accessor :rails_branch, :database, :exception_handling, :monitoring, :branch_management, :rails_strategy, :link_rails_root,
     :ie6_blocking, :javascript_library, :template_engine, :compass_css_framework, :design, :require_activation,
     :mocking, :smtp_address, :smtp_domain, :smtp_username, :smtp_password, :capistrano_user, :capistrano_repo_host, :capistrano_production_host,
     :capistrano_staging_host, :exceptional_api_key, :hoptoad_api_key, :newrelic_api_key, :notifier_email_from, :default_url_options_host,        
     :template_paths, :template_options, :controller_type, :branches, :post_creation, :github_username, :github_token, :github_public
  
    def add_template_path(path, placement = :prepend)
      if placement == :prepend
        @template_paths.unshift path
      elsif placement == :append
        @template_paths.push path
      end
    end
    
    # TODO: List of attributes should be data driven
    def init_template_framework(template, root)
      @template_paths = [File.expand_path(File.dirname(template), File.join(root,'..'))]
    end

    def load_options
      # Option set-up
      @template_options = load_template_config_file('config.yml')

      @rails_branch = template_options["rails_branch"]
      @rails_branch = "2-3-stable" if @rails_branch.nil?

      @database = template_options["database"].nil? ? ask("Which database? postgresql (default), mysql, sqlite").downcase : template_options["database"]
      @database = "postgresql" if @database.nil?

      @exception_handling = template_options["exception_handling"].nil? ? ask("Which exception reporting? exceptional (default), hoptoad").downcase : template_options["exception_handling"]
      @exception_handling = "exceptional" if @exception_handling.nil?

      @monitoring = template_options["monitoring"].nil? ? ask("Which monitoring? new_relic (default), scout").downcase : template_options["monitoring"]
      @monitoring = "new_relic" if @monitoring.nil?

      @branch_management = template_options["branch_management"].nil? ? ask("Which branch management? piston (default), braid, git, none").downcase : template_options["branch_management"]
      @branch_management = "piston" if @branch_management.nil?

      @rails_strategy = template_options["rails_strategy"].nil? ? ask("Which Rails strategy? vendored (default), gem").downcase : template_options["rails_strategy"]
      @rails_strategy = "vendored" if @rails_strategy.nil?

      @link_rails_root = template_options["link_rails_root"]
      @link_rails_root = "~/rails" if @link_rails_root.nil?

      @ie6_blocking = template_options["ie6_blocking"].nil? ? ask("Which IE 6 blocking? none, light (default), ie6nomore").downcase : template_options["ie6_blocking"]
      @ie6_blocking = "light" if @ie6_blocking.nil?

      @javascript_library = template_options["javascript_library"].nil? ? ask("Which javascript library? prototype (default), jquery").downcase : template_options["javascript_library"]
      @javascript_library = "prototype" if @javascript_library.nil?

      @template_engine = template_options["template_engine"].nil? ? ask("Which template engine? erb (default), haml").downcase : template_options["template_engine"]
      @template_engine = "erb" if @template_engine.nil?

      @compass_css_framework = template_options["compass_css_framework"]
      @compass_css_framework = "blueprint" if @compass_css_framework.nil?

      @design = template_options["design"].nil? ? ask("Which design? none (default), bluetrip, compass").downcase : template_options["design"]
      @design = "none" if @design.nil?

      @require_activation = (template_options["require_activation"].to_s == "true")

      @mocking = template_options["mocking"].nil? ? ask("Which mocking library? rr, mocha (default)").downcase : template_options["mocking"]
      @mocking = "mocha" if @mocking.nil?

      @controller_type = template_options["controller_type"].nil? ? ask("Which controller strategy? rails (default), inherited_resources").downcase : template_options["controller_type"]
      @controller_type = "default" if @controller_type.nil? || @controller_type == 'rails'

      @github_username = template_options["github_username"]
      @github_token = template_options["github_token"]
      @github_public = template_options["github_public"]
      @smtp_address = template_options["smtp_address"]
      @smtp_domain = template_options["smtp_domain"]
      @smtp_username = template_options["smtp_username"]
      @smtp_password = template_options["smtp_password"]
      @capistrano_user = template_options["capistrano_user"]
      @capistrano_repo_host = template_options["capistrano_repo_host"]
      @capistrano_production_host = template_options["capistrano_production_host"]
      @capistrano_staging_host = template_options["capistrano_staging_host"]
      @exceptional_api_key = template_options["exceptional_api_key"]
      @hoptoad_api_key = template_options["hoptoad_api_key"]
      @newrelic_api_key = template_options["newrelic_api_key"]
      @notifier_email_from = template_options["notifier_email_from"]
      @default_url_options_host = template_options["default_url_options_host"]

      @branches = template_options["git_branches"]
    
      @post_creation = template_options["post_creation"]
  end

# File Management 
    def download(from, to = from.split("/").last)
      #run "curl -s -L #{from} > #{to}"
      file to, open(from).read
    rescue
      puts "Can't get #{from} - Internet down?"
      exit!
    end
 
    # grab an arbitrary file from github
    def file_from_repo(github_user, repo, sha, filename, to = filename)
      download("http://github.com/#{github_user}/#{repo}/raw/#{sha}/#{filename}", to)
    end

    def load_from_file_in_template(file_name, parent_binding = nil, file_group = 'default', file_type = :pattern)
      base_name = file_name.gsub(/^\./, '')
      begin
        if file_type == :config
          contents = {}
        else
          contents = ''
        end
        paths = template_paths

        paths.each do |template_path|
          full_file_name = File.join(template_path, file_type.to_s.pluralize, file_group, base_name)
          debug_log "Searching for #{full_file_name} ... "

          next unless File.exists? full_file_name
          debug_log "Found!"

          if file_type == :config
            contents = open(full_file_name) { |f| YAML.load(f) }
          else
            contents = open(full_file_name) { |f| f.read }
          end
          if contents && parent_binding
            contents = eval("\"" + contents.gsub('"','\\"') + "\"", parent_binding)
          end
          # file loaded, stop searching
          break if contents

        end
        contents
      rescue => ex
        debug_log "Error in load_from_file_in_template #{file_name}"
        debug_log ex.message
      end
    end

    # Load a snippet from a file
    def load_snippet(snippet_name, snippet_group = "default")
      load_from_file_in_template(snippet_name, nil, snippet_group, :snippet)  
    end

    # Load a pattern from a file, potentially with string interpolation
    def load_pattern(pattern_name, pattern_group = "default", parent_binding = nil)
      load_from_file_in_template(pattern_name, parent_binding, pattern_group, :pattern)
    end

    # YAML.load a configuration from a file
    def load_template_config_file(config_file_name, config_file_group = "default")
      load_from_file_in_template(config_file_name, nil, config_file_group, :config )
    end

# SCM and Branch Management 
     def commit_state(comment)
       git :add => "."
       git :commit => "-am '#{comment}'"
     end

    # sudo gem install piston on your dev box before using these
    # Piston locking support with git requires Piston 2.0.3+
    # Piston branch management with git 1.6.3 requires Piston 2.0.5+

    # Use Piston to install and lock a plugin:
    # piston_plugin 'stuff', :git => 'git://github.com/whoever/stuff.git'
    # Use Piston to install a plugin without locking:
    # piston_plugin 'stuff', :git => 'git://github.com/whoever/stuff.git', :lock => false
    def piston_plugin(name, options={})
      lock = options.fetch(:lock, true)

      if options[:git] || options[:svn]
        in_root do
          run("piston import #{options[:svn] || options[:git]} vendor/plugins/#{name}")
          run("piston lock vendor/plugins/#{name}") if lock
          commit_state("Added pistoned #{name}")
        end
        log "plugin installed #{'and locked ' if lock}with Piston:", name
      else
        log "! no git or svn provided for #{name}.  skipping..."
      end
    end

    # Use Piston to install and lock current Rails edge (master):
    # piston_rails
    # Use Piston to install but not lock current Rails edge (master):
    # piston_rails :lock => false
    # Use Piston to install and lock edge of a specific Rails branch:
    # piston_rails :branch => "2-3-stable"
    # Use Piston to install but not lock edge of a specific Rails branch:
    # piston_rails, :branch => "2-3-stable", :lock => false
    def piston_rails(options={})
      lock = options.fetch(:lock, true)

      if options[:branch]
        in_root do
          run("piston import --commit #{options[:branch]} git://github.com/rails/rails.git vendor/rails")
          commit_state("Added pistoned Rails using the edge of the #{options[:branch]} branch")
          if lock
            run("piston lock vendor/rails")
            commit_state("Locked pistoned rails")
          end
        end
      else
        in_root do
          run("piston import git://github.com/rails/rails.git vendor/rails")
          commit_state("Added pistoned Rails edge")
          if lock
            run("piston lock vendor/rails")
            commit_state("Locked pistoned rails")
          end
        end
      end

      log "rails installed #{'and locked ' if lock}with Piston", options[:branch]
    end

    # braid support is experimental and largely untested
    def braid_plugin(name, options={})
      if options[:git]
        in_root do
          run("braid add -p #{options[:git]}")
          commit_state("Added braided #{name}")
        end
        log "plugin installed with Braid:", name
      else
        log "! no git provided for #{name}.  skipping..."
      end
    end

    def braid_rails(options={})
      if options[:branch]
        log "! branch support for Braid is not yet implemented"
      else
        in_root do
          run("braid add git://github.com/rails/rails.git vendor/rails")
          log "rails installed with Braid"
        end
      end
    end

    # cloning rails is experimental and somewhat untested
    def clone_rails(options={})
      if options[:submodule]
        in_root do
          if options[:branch] && options[:branch] != "master"
            git :submodule => "add git://github.com/rails/rails.git vendor/rails -b #{options[:branch]}"
          else
            git :submodule => "add git://github.com/rails/rails.git vendor/rails"
          end
        end
      else
        inside 'vendor' do
          run('git clone git://github.com/rails/rails.git')
        end
        if options[:branch] && options[:branch] != "master"
          inside 'vendor/rails' do
            run("git branch --track #{options[:branch]} origin/#{options[:branch]}")
            run("git checkout #{options[:branch]}")
          end
        end
      end

      log "rails installed #{'and submoduled ' if options[:submodule]}from GitHub", options[:branch]
    end

    # setup the specified branches in the git repo
    def git_branch_setup
      if !branches.nil?
        default_branch = "master"
        branches.each do |name, default|
          if name != "master"
            git :branch => name
            default_branch = name if !default.nil?
          end
        end
        git :checkout => default_branch if default_branch != "master"
        log "set up branches #{branches.keys.join(', ')}"
      end
    end
    
# Rails Management

    # update rails bits in application after vendoring a new copy of rails
    # we need to do this the hard way because we want to overwrite without warning
    # TODO: Can we introspect the actual rake:update task to get a current list of subtasks?
    def update_app
      in_root do
        run("echo 'a' | rake rails:update:scripts")
        run("echo 'a' | rake rails:update:javascripts")
        run("echo 'a' | rake rails:update:configs")
        run("echo 'a' | rake rails:update:application_controller")
      end
    end

    # remove the prototype framework
    def remove_prototype
      run "rm public/javascripts/controls.js"
      run "rm public/javascripts/dragdrop.js"
      run "rm public/javascripts/effects.js"
      run "rm public/javascripts/prototype.js"
    end

    def install_plugin (name, options)
      case @branch_management
      when 'none'
        plugin name, options
      when 'piston'
        piston_plugin name, options
      when 'braid'
        braid_plugin name, options
      when 'git'
        plugin name, options.merge(:submodule => true)
      end
    end

    def install_rails (options)
      case @branch_management
      when 'none'
        clone_rails options
      when 'piston'
        piston_rails options
      when 'braid'
        braid_rails options
      when 'git'
        clone_rails options.merge(:submodule => true)
      end
    end
    
# Mocking generators

    def generate_stub(object_name, method_name, return_value)
      if @mocking == "rr"
        "stub(#{object_name}).#{method_name}{ #{return_value} }"
      elsif @mocking == "mocha"
        "#{object_name}.stubs(:#{method_name}).returns(#{return_value})"
      end
    end

    def generate_any_instance_stub(object_name, method_name, return_value)
      if @mocking == "rr"
        "stub.instance_of(#{object_name}).#{method_name}{ #{return_value} }"
      elsif @mocking == "mocha"
        "#{object_name}.any_instance.stubs(:#{method_name}).returns(#{return_value})"
      end
    end

    def generate_expectation(object_name, method_name, parameter = nil)
      if parameter
        if @mocking == "rr"
          "mock(#{object_name}).#{method_name}(#{parameter})"
        elsif @mocking == "mocha"
          "#{object_name}.expects(:#{method_name}).with(#{parameter})"
        end
      else
        if @mocking == "rr"
          "mock(#{object_name}).#{method_name}"
        elsif @mocking == "mocha"
          "#{object_name}.expects(:#{method_name})"
        end
      end
    end

    def generate_pure_stub(stub_name)
      if @mocking == "rr"
        "stub!('#{stub_name}')"
      elsif @mocking == "mocha"
        "stub('#{stub_name}')"
      end
    end
  
# Heroku management

    # Run a command with the Heroku gem.
    #
    # ==== Examples
    #
    #   heroku :create
    #   heroku :rake => "db:migrate"
    #
    def heroku(command = {})
      in_root do
        if command.is_a?(Symbol)
          log 'running', "heroku #{command}"
          run "heroku #{command}"
        else
          command.each do |command, options|
            log 'running', "heroku #{command} #{options}"
            run("heroku #{command} #{options}")
          end
        end
      end
    end

# post-creation hooks
    def execute_post_creation_hooks
      if !post_creation.nil?
        post_creation.each do |name, options|
          if name == 'heroku'
            git :checkout => "master"
            rake "gems:specify", :env => "production"
            commit_state "added gem manifest"
            heroku :create
            git :push => "heroku master"
            heroku :rake => "db:migrate"
            heroku :restart
            heroku :open
            log "set up application at Heroku"
          end
          if name == 'github'
            run "curl -F 'login=#{github_username}' -F 'token=#{github_token}' -F 'name=#{current_app_name}' -F 'public=#{github_public}' http://github.com/api/v2/json/repos/create"
            git :remote => "add origin git@github.com:#{github_username}/#{current_app_name}.git"
            git :push => "origin master"
            if !branches.nil?
              default_branch = "master"
              branches.each do |name, default|
                if name != "master"
                  git :push => "origin #{name}"
                  default_branch = name if !default.nil?
                end
              end
              git :checkout => default_branch if default_branch != "master"
            end
            log "set up application at GitHub"
          end
        end
      end
    end

# Gem management
    def install_gems
      gems = load_template_config_file('gems.yml')  
      install_on_current(gems)
      add_to_project(gems)
    end

    # If the geminstaller gem is present, use to to bootstrap the other
    # needed gems on to the dev box so that rake succeeds
    def install_on_current(gems)
      begin
        require 'geminstaller'
        # Transform the gem array to the form that geminstaller wants to see
        gem_array = []
        gems.each do |name, value|
          if value[:if].nil? || eval(value[:if])
            h = Hash.new
            h["name"] = name
            if value[:options] && value[:options][:version]
              h["version"] = value[:options][:version]
            end
            gem_array.push h
          end
        end
        
        if !gem_array.empty? 
          geminstaller_hash = {"defaults"=>{"install_options"=>"--no-ri --no-rdoc"}, "gems"=> gem_array}
          in_root do
            File.open( 'geminstaller.yml', 'w' ) do |out|
              YAML.dump( geminstaller_hash, out )
            end
            run 'geminstaller'
            log "installed gems on current machine"
          end
        end
        
      rescue LoadError
      end
    end
      
    def add_to_project(gems)
      gems.each do |name, value|
        if value[:if].nil? || eval(value[:if])
          gem name, value[:options]
        end
      end
    end
    
  end
end