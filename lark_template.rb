require 'open-uri'
require 'yaml'
require 'base64'
require 'cgi'

# Turn on for noisy logging during template generation
DEBUG_LOGGING = false

# Utility Methods
 
# download, from_repo, and commit_state methods swiped from 
# http://github.com/Sutto/rails-template/blob/07b044072f3fb0b40aea27b713ca61515250f5ec/rails_template.rb
 
def download(from, to = from.split("/").last)
  #run "curl -s -L #{from} > #{to}"
  file to, open(from).read
rescue
  puts "Can't get #{from} - Internet down?"
  exit!
end
 
def from_repo(github_user, from, to = from.split("/").last)
  download("http://github.com/#{github_user}/rails-template/raw/master/#{from}", to)
end
 
def commit_state(comment)
  git :add => "."
  git :commit => "-am '#{comment}'"
end

# grab an arbitrary file from github
def file_from_repo(github_user, repo, sha, filename, to = filename)
  download("http://github.com/#{github_user}/#{repo}/raw/#{sha}/#{filename}", to)
end

def debug_log(msg)
  if DEBUG_LOGGING
    log msg
  end
end

@template = template
@root = root

def load_from_file_in_template(file_name, parent_binding = nil, file_group = 'default', file_type = :pattern)
  base_name = file_name.gsub(/^\./, '')
  begin
    if file_type == :config
      contents = {}
    else
      contents = ''
    end
    template_paths = [
                      File.expand_path(File.join(ENV['HOME'],'.big_old_rails_template')),
                      File.expand_path(File.dirname(@template), File.join(@root,'..'))
                     ]

    template_paths.each do |template_path|
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
  rescue
    debug_log "Error in load_from_file_in_template #{file_name}"
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

# Piston and braid methods out of my own head
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

# update rails bits in application after vendoring a new copy of rails
# we need to do this the hard way because we want to overwrite without warning
# TODO: Can we introspect the actual rake:update task to get a current list of subtasks?
def update_app
  in_root do
    run("echo 'a' | rake rails:update:scripts")
    run("echo 'a' | rake rails:update:javascripts")
    run("echo 'a' | rake rails:update:configs")
    run("echo 'a' | rake rails:update:application_controller")

    if @javascript_library != "prototype"
      run "rm public/javascripts/controls.js"
      run "rm public/javascripts/dragdrop.js"
      run "rm public/javascripts/effects.js"
      run "rm public/javascripts/prototype.js"
    end
  end
end

current_app_name = File.basename(File.expand_path(root))

# Option set-up
template_options = load_template_config_file('config.yml')

rails_branch = template_options["rails_branch"]
rails_branch = "2-3-stable" if rails_branch.nil?

database = template_options["database"].nil? ? ask("Which database? postgresql (default), mysql, sqlite").downcase : template_options["database"]
database = "postgresql" if database.nil?

exception_handling = template_options["exception_handling"].nil? ? ask("Which exception reporting? exceptional (default), hoptoad").downcase : template_options["exception_handling"]
exception_handling = "exceptional" if exception_handling.nil?

monitoring = template_options["monitoring"].nil? ? ask("Which monitoring? new_relic (default), scout").downcase : template_options["monitoring"]
monitoring = "new_relic" if monitoring.nil?

@branch_management = template_options["branch_management"].nil? ? ask("Which branch management? piston (default), braid, git, none").downcase : template_options["branch_management"]
@branch_management = "piston" if @branch_management.nil?

rails_strategy = template_options["rails_strategy"].nil? ? ask("Which Rails strategy? vendored (default), gem").downcase : template_options["rails_strategy"]
rails_strategy = "vendored" if rails_strategy.nil?

link_rails_root = template_options["link_rails_root"]
link_rails_root = "~/rails" if link_rails_root.nil?

ie6_blocking = template_options["ie6_blocking"].nil? ? ask("Which IE 6 blocking? none, light (default), ie6nomore").downcase : template_options["ie6_blocking"]
ie6_blocking = "light" if ie6_blocking.nil?

@javascript_library = template_options["javascript_library"].nil? ? ask("Which javascript library? prototype (default), jquery").downcase : template_options["javascript_library"]
@javascript_library = "prototype" if @javascript_library.nil?

template_engine = template_options["template_engine"].nil? ? ask("Which template engine? erb (default), haml").downcase : template_options["template_engine"]
template_engine = "erb" if template_engine.nil?

compass_css_framework = template_options["compass_css_framework"]
compass_css_framework = "blueprint" if compass_css_framework.nil?

design = template_options["design"].nil? ? ask("Which design? none (default), bluetrip, compass").downcase : template_options["design"]
design = "none" if design.nil?

require_activation = (template_options["require_activation"].to_s == "true")

@mocking = template_options["mocking"].nil? ? ask("Which mocking library? rr (default), mocha").downcase : template_options["mocking"]
@mocking = "rr" if @mocking.nil?

smtp_address = template_options["smtp_address"]
smtp_domain = template_options["smtp_domain"]
smtp_username = template_options["smtp_username"]
smtp_password = template_options["smtp_password"]
capistrano_user = template_options["capistrano_user"]
capistrano_repo_host = template_options["capistrano_repo_host"]
capistrano_production_host = template_options["capistrano_production_host"]
capistrano_staging_host = template_options["capistrano_staging_host"]
exceptional_api_key = template_options["exceptional_api_key"]
hoptoad_api_key = template_options["hoptoad_api_key"]
newrelic_api_key = template_options["newrelic_api_key"]
notifier_email_from = template_options["notifier_email_from"]
default_url_options_host = template_options["default_url_options_host"]

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

# Actual application generation starts here

# Delete unnecessary files
run "rm README"
run "rm public/index.html"
run "rm public/favicon.ico"

# Set up git repository
# must do before running piston or braid
git :init

# Set up gitignore and commit base state
file '.gitignore', load_pattern('.gitignore')

if @branch_management == "git"
  file "lib/tasks/git.rake", load_pattern("lib/tasks/git.rake", "git")
end

commit_state "base application"

# plugins
plugins = load_template_config_file('plugins.yml')  
plugins.each do |name, value|
  if value[:if].nil? || eval(value[:if])
    install_plugin name, value[:options]
  end
end

if @branch_management == "git"
  rake("git:submodules:init")
end

# gems
gems = load_template_config_file('gems.yml')  
gems.each do |name, value|
  if value[:if].nil? || eval(value[:if])
    gem name, value[:options]
  end
end

# assume gems are already on dev box, so don't install    
# rake("gems:install", :sudo => true)

commit_state "Added plugins and gems"

# environment updates
in_root do
  run 'cp config/environments/production.rb config/environments/staging.rb'
end
environment 'config.middleware.use "Rack::Bug"', :env => 'development'
environment 'config.middleware.use "Rack::Bug"', :env => 'staging'

environment 'config.action_mailer.delivery_method = :smtp', :env => 'production'
environment 'config.action_mailer.delivery_method = :smtp', :env => 'staging'

commit_state "Set up staging environment and hooked up Rack::Bug"

# make sure HAML files get searched if we go that route
file '.ackrc', load_pattern('.ackrc')

# some files for app
if @javascript_library == "prototype"
  download "http://livevalidation.com/javascripts/src/1.3/livevalidation_prototype.js", "public/javascripts/livevalidation.js"
elsif @javascript_library == "jquery"
  file_from_repo "ffmike", "jquery-validate", "master", "jquery.validate.min.js", "public/javascripts/jquery.validate.min.js"
  rake("jrails:js:scrub")
  rake("jrails:js:install")
end

if design == "bluetrip"
  inside('public') do
    run('mkdir img')
  end
  inside('public/img') do
    run('mkdir icons')
  end
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/ie.css", "public/stylesheets/ie.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/print.css", "public/stylesheets/print.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/screen.css", "public/stylesheets/screen.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "css/style.css", "public/stylesheets/style.css"
  file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "img/grid.png", "public/img/grid.png"
  %w(cross doc email external feed im information key pdf tick visited xls).each do |icon|
    file_from_repo "mikecrittenden", "bluetrip-css-framework", "master", "img/icons/#{icon}.png", "public/img/icons/#{icon}.png"
  end
end

if design == "compass"
  compass_css_framework = template_options["compass_css_framework"].nil? ? ask("Compass CSS Framework? blueprint (default), 960").downcase : template_options["compass_css_framework"]
  compass_css_framework = "blueprint" if compass_css_framework.blank?

  compass_sass_dir = "app/stylesheets"
  compass_css_dir = "public/stylesheets"


  # load any compass framework plugins
  if compass_css_framework =~ /960/
    plugin_require = "-r ninesixty"
  end

  # build out compass command
  compass_command = "compass --rails -f #{compass_css_framework} . --css-dir=#{compass_css_dir} --sass-dir=#{compass_sass_dir} "
  compass_command << plugin_require if plugin_require

  # Require compass during plugin loading
  file 'vendor/plugins/compass/init.rb', <<-CODE
  # This is here to make sure that the right version of sass gets loaded (haml 2.2) by the compass requires.
  require 'compass'
  CODE

  # integrate it!
  run "haml --rails ."
  run compass_command

  puts "Compass (with #{compass_css_framework}) is all setup, have fun!"
end

if design != "compass" && template_engine == "haml"
  run "haml --rails ."
end

flash_class =  load_snippet('flash_class', design)

file 'app/views/layouts/_flashes.html.erb', load_pattern('app/views/layouts/_flashes.html.erb', 'default', binding)

javascript_include_tags = load_snippet('javascript_include_tags', @javascript_library)

extra_stylesheet_tags = load_snippet('extra_stylesheet_tags', design)
footer_class = load_snippet('footer_class', design)

file 'app/views/layouts/application.html.erb', load_pattern('app/views/layouts/application.html.erb', 'default', binding)

# rakefile for use with inaction_mailer
rakefile 'mail.rake', load_pattern('lib/tasks/mail.rake')

application_styles = load_snippet('application_styles', design)

file 'public/stylesheets/application.css', load_pattern('public/stylesheets/application.css', 'default', binding)

generate(:formtastic_stylesheets)

file 'app/controllers/application_controller.rb', load_pattern('app/controllers/application_controller.rb')
file 'app/helpers/application_helper.rb', load_pattern('app/helpers/application_helper.rb')
file 'app/helpers/layout_helper.rb', load_pattern('app/helpers/layout_helper.rb')

# initializers
initializer 'requires.rb', load_pattern('config/initializers/requires.rb')
initializer 'admin_data.rb', load_pattern('config/initializers/admin_data.rb')
initializer 'live_validations.rb', load_pattern('config/initializers/live_validations.rb', @javascript_library) 

base64_user_name = Base64.encode64(smtp_username) unless smtp_username.blank? 
base64_password = Base64.encode64(smtp_password) unless smtp_username.blank? 

initializer 'mail.rb', load_pattern('config/initializers/mail.rb', 'default', binding)
initializer 'date_time_formats.rb', load_pattern('config/initializers/date_time_formats.rb')
initializer 'query_trace.rb', load_pattern('config/initializers/query_trace.rb')
initializer 'backtrace_silencers.rb', load_pattern('config/initializers/backtrace_silencers.rb')

if exception_handling == "hoptoad"
  initializer 'hoptoad.rb', load_pattern('config/initializers/hoptoad.rb')
end

commit_state "application files and initializers"

# deployment
capify!

file 'config/deploy.rb', load_pattern('config/deploy.rb', 'default', binding)
file 'config/deploy/production.rb', load_pattern('config/deploy/production.rb', 'default', binding)
file 'config/deploy/staging.rb', load_pattern('config/deploy/staging.rb', 'default', binding)

commit_state "deployment files"

# error handling
if exception_handling == "exceptional"
  file 'config/exceptional.yml', load_pattern('config/exceptional.yml', 'default', binding)
end

# performance monitoring
if monitoring == "new_relic"
  file 'config/newrelic.yml', load_pattern('config/newrelic.yml', 'default', binding)
end

if monitoring == "scout"
  file 'config/scout.yml', load_pattern('config/scout.yml', 'default', binding)
end

# database
file 'config/database.yml', load_pattern("config/database.#{database}.yml", 'default', binding)
file 'db/populate/01_sample_seed.rb', load_pattern('db/populate/01_sample_seed.rb')

if require_activation
  account_create_flash = "Your account has been created. Please check your e-mail for your account activation instructions."
else
  account_create_flash = "Account registered!"
end

# locale
file 'config/locales/en.yml', load_pattern('config/locales/en.yml', 'default', binding)

commit_state "configuration files"

# testing
file 'test/exemplars/sample_exemplar.rb', load_pattern('test/exemplars/sample_exemplar.rb')
mock_include = ""
if @mocking == "rr"
  mock_include = "  include RR::Adapters::TestUnit"
end
file 'test/test_helper.rb', load_pattern('test/test_helper.rb', 'default', binding)

extra_notifier_test = ""
if require_activation
  extra_notifier_test = load_snippet('extra_notifier_test', 'require_activation')
  extra_notifier_test.sub!('#{notifier_email_from}', notifier_email_from)
end

file 'test/unit/notifier_test.rb', load_pattern('test/unit/notifier_test.rb', 'default', binding)

welcome_callback = ""
extra_user_tests = ""
if require_activation
  if @mocking == "rr"
    extra_user_tests = load_snippet('extra_user_tests', 'require_activation')
  elsif @mocking == "mocha"
    extra_user_tests = load_snippet('extra_user_tests_mocha', 'require_activation')
  end
else
  welcome_callback = "should_callback :send_welcome_email, :after_create"
end

file 'test/unit/user_test.rb', load_pattern('test/unit/user_test.rb', 'default', binding)

file 'test/shoulda_macros/authlogic.rb', load_pattern('test/shoulda_macros/authlogic.rb')
file 'test/shoulda_macros/filter.rb', load_pattern('test/shoulda_macros/filter.rb')
file 'test/shoulda_macros/helpers.rb', load_pattern('test/shoulda_macros/helpers.rb')

file 'test/exemplars/user_exemplar.rb', load_pattern('test/exemplars/user_exemplar.rb')

file 'test/unit/user_session_test.rb', load_pattern('test/unit/user_session_test.rb')

file 'test/unit/helpers/application_helper_test.rb', load_pattern('test/unit/helpers/application_helper_test.rb')


if require_activation
  file 'test/functional/accounts_controller_test.rb', load_pattern('test/functional/accounts_controller_test.rb', 'require_activation', binding)
  file 'test/functional/activations_controller_test.rb', load_pattern('test/functional/activations_controller_test.rb', 'require_activation', binding)
else
  file 'test/functional/accounts_controller_test.rb', load_pattern('test/functional/accounts_controller_test.rb', 'default', binding)
end

generate_user_block = ""
if require_activation
  generate_user_block = load_snippet('generate_user_block', 'require_activation')
else
  generate_user_block = load_snippet('generate_user_block')
end

file 'test/functional/application_controller_test.rb', load_pattern('test/functional/application_controller_test.rb', 'default', binding)

if require_activation
  file 'test/functional/users_controller_test.rb', load_pattern('test/functional/users_controller_test.rb', 'require_activation', binding)
else
  file 'test/functional/users_controller_test.rb', load_pattern('test/functional/users_controller_test.rb', 'default', binding)
end

file 'test/functional/user_sessions_controller_test.rb', load_pattern('test/functional/user_sessions_controller_test.rb', 'default', binding)

upgrade_test = ''
if ie6_blocking == 'light'
  upgrade_test = load_snippet('ie6_blocking_light_upgrade_test')
end

file 'test/functional/pages_controller_test.rb', load_pattern('test/functional/pages_controller_test.rb', 'default', binding)
file 'test/functional/password_resets_controller_test.rb', load_pattern('test/functional/password_resets_controller_test.rb', 'default', binding)

new_user_contained_text = 'I18n.t("flash.accounts.create.notice")'

new_user_extra_fields = ""
unless require_activation
  new_user_extra_fields = load_snippet('new_user_extra_fields')
end

file 'test/integration/new_user_can_register_test.rb', load_pattern('test/integration/new_user_can_register_test.rb', 'default', binding)
file 'test/integration/user_can_login_test.rb', load_pattern('test/integration/user_can_login_test.rb', 'default', binding)
file 'test/integration/user_can_logout_test.rb', load_pattern('test/integration/user_can_logout_test.rb', 'default', binding)

commit_state "basic tests"

# authlogic setup

account_create_block = ""
if require_activation
  account_create_block = load_snippet('account_create_block', 'require_activation')
else
  account_create_block = load_snippet('account_create_block')
end

file 'app/controllers/accounts_controller.rb', load_pattern('app/controllers/accounts_controller.rb', 'default', binding)

if require_activation
  file 'app/controllers/activations_controller.rb', load_pattern('app/controllers/activations_controller.rb', 'require_activation')
end

file 'app/controllers/password_resets_controller.rb', load_pattern('app/controllers/password_resets_controller.rb')
file 'app/controllers/user_sessions_controller.rb', load_pattern('app/controllers/user_sessions_controller.rb')

user_create_block = ''
if require_activation
  user_create_block = load_snippet('user_create_block', 'require_activation')
else
  user_create_block = load_snippet('user_create_block')
end

file 'app/controllers/users_controller.rb' , load_pattern('app/controllers/users_controller.rb', 'default', binding)

activation_instructions_block = ""
if require_activation
  activation_instructions_block = load_snippet('activation_instructions_block', 'require_activation')
end

file 'app/models/notifier.rb', load_pattern('app/models/notifier.rb', 'default', binding)

if require_activation
  file 'app/models/user.rb', load_pattern('app/models/user.rb', 'require_activation')
else
  file 'app/models/user.rb', load_pattern('app/models/user.rb')
end

file 'app/models/user_session.rb', load_pattern('app/models/user_session.rb')

if require_activation
  file 'app/views/activations/new.html.erb', load_pattern('app/views/activations/new.html.erb', 'require_activation')
  file 'app/views/notifier/activation_instructions.html.erb', load_pattern('app/views/notifier/activation_instructions.html.erb', 'require_activation')
end

file 'app/views/notifier/password_reset_instructions.html.erb', load_pattern('app/views/notifier/password_reset_instructions.html.erb')
file 'app/views/notifier/welcome_email.html.erb', load_pattern('app/views/notifier/welcome_email.html.erb')
file 'app/views/password_resets/edit.html.erb', load_pattern('app/views/password_resets/edit.html.erb')
file 'app/views/password_resets/new.html.erb', load_pattern('app/views/password_resets/new.html.erb')

if design == "bluetrip"
  file 'app/views/user_sessions/new.html.erb', load_pattern('app/views/user_sessions/new.html.erb', 'bluetrip')
else
  file 'app/views/user_sessions/new.html.erb', load_pattern('app/views/user_sessions/new.html.erb')
end

file 'app/views/users/index.html.erb', load_pattern('app/views/users/index.html.erb')

password_input_block = ""
password_input_block = load_snippet('password_input_block') unless require_activation

file 'app/views/users/_form.html.erb', load_pattern('app/views/users/_form.html.erb', 'default', binding)

if design == "bluetrip" 
  file 'app/views/users/edit.html.erb', load_pattern('app/views/users/edit.html.erb', 'bluetrip')
else
  file 'app/views/users/edit.html.erb', load_pattern('app/views/users/edit.html.erb')
end

if design == "bluetrip"
  file 'app/views/users/new.html.erb', load_pattern('app/views/users/new.html.erb', 'bluetrip')
else
  file 'app/views/users/new.html.erb', load_pattern('app/views/users/new.html.erb')
end

file 'app/views/users/show.html.erb', load_pattern('app/views/users/show.html.erb')

if require_activation
  file 'db/migrate/01_create_users.rb', load_pattern('db/migrate/01_create_users.rb', 'require_activation')
else
  file 'db/migrate/01_create_users.rb', load_pattern('db/migrate/01_create_users.rb')
end

file 'db/migrate/02_create_sessions.rb', load_pattern('db/migrate/02_create_sessions.rb')

commit_state "basic Authlogic setup"

# static pages
ie6_method = ""
if ie6_blocking == "light"
  ie6_method = load_snippet("ie6_method")
end

file 'app/controllers/pages_controller.rb', load_pattern('app/controllers/pages_controller.rb', 'default', binding)

ie6_warning = ""
if ie6_blocking == "light"
  ie6_warning = load_snippet('ie6_blocking_light_warning')
elsif ie6_blocking == "ie6nomore"
  ie6_warning =  load_snippet('ie6_blocking_ie6nomore_warning')
end

top_menu_class = ""
left_menu_class = ""
main_with_left_menu_class = ""
if design == "bluetrip"
  top_menu_class = load_snippet("top_menu_class", "bluetrip")
  left_menu_class = load_snippet("left_menu_class", "bluetrip")
  main_with_left_menu_class = load_snippet("main_with_left_menu_class", "bluetrip")
end

file 'app/views/pages/home.html.erb', load_pattern('app/views/pages/home.html.erb', 'default', binding)
file 'app/views/pages/css_test.html.erb', load_pattern('app/views/pages/css_test.html.erb')
if ie6_blocking == 'light'
  file 'app/views/pages/upgrade.html.erb', load_pattern('app/views/pages/upgrade.html.erb', 'default', binding)
end

file 'doc/README_FOR_APP', load_pattern('doc/README_FOR_APP', 'default', binding)

commit_state "static pages"

activation_routes = ""
if require_activation
  activation_routes = load_snippet('activation_routes', 'require_activation')
end

# simple default routing
file 'config/routes.rb', load_pattern('config/routes.rb', 'default', binding)

commit_state "routing"

# optionally convert html/erb/css to haml/sass
if template_engine == 'haml'
  def get_indent(line)
    line = line.to_s
    space_areas = line.scan(/^\s+/)
    space_areas.empty? ? 0 : (space_areas.first.size / 2)
  end

  def block_start?(line)
    block_starters = [/\s+do/, /^-\s+while/, /^-\s+module/, /^-\s+begin/,
                      /^-\s+case/, /^-\s+class/, /^-\s+unless/, /^-\s+for/, 
                      /^-\s+until/, /^-\s*if/]

    line = line.to_s
    line.strip =~ /^-/ && block_starters.any?{|bs| line.strip =~ bs}
  end

  def block_end?(line)
    line = line.to_s
    line.strip =~ /^-\send$/
  end

  def ie_block_start?(line)
    line = line.to_s
    line =~ /\[if/i && line =~ /IE/ && line.strip =~ /\]>$/
  end

  def ie_block_end?(line)
    line = line.to_s
    line =~ /<!\[endif\]/i
  end

  def comment_line?(line)
    line = line.to_s
    line.strip =~ /^\//
  end

  def indent(line, steps = 0)
    line = line.to_s
    exceptions = [/\s+else\W/, /^-\s+elsif/, /^-\s+when/, /^-\s+ensure/, /^-\s+rescue/]
    return if exceptions.any?{|ex| line.strip =~ ex}

    steps ||= 0
    line = line.to_s
    ("  " * steps) + line
  end

  def alter_lines(lines, altered_lines)
    altered_lines.each do |pair|
      line_number, text = pair
      lines[line_number] = text
    end
    lines
  end

  def indent_lines(lines, indented_lines)
    indented_lines.each do |pair|
      line_number, indent_by = pair
      lines[line_number] = indent(lines[line_number], indent_by)
    end
    lines
  end

  def remove_lines(lines, goner_lines)
    goner_lines.each do |i|
      lines[i] = nil
    end
    lines.compact
  end
  
  in_root do
    Dir["app/views/**/*.erb"].each do |origin|
      destination = origin.gsub(/\.erb$/, '.haml')
      run "html2haml -rx #{origin} #{destination}"
      
      # Auto-fix for haml indentation. Likely not very reliable.
      stack = []
      lines = File.readlines(destination)
      line_number = lines.size
      goner_lines = []
      indented_lines = []
      altered_lines = []
      inside_ie_block = false
      just_passed_ie_block = false

      lines.reverse_each do |line|
        line_number -= 1

        if just_passed_ie_block
          altered_lines << [line_number, line.sub('/', "/" + just_passed_ie_block)]
          just_passed_ie_block = false
        elsif ie_block_start?(line)
          goner_lines << line_number
          inside_ie_block = false
          stack.pop
          just_passed_ie_block = line.strip.chop
        elsif ie_block_end?(line)
          goner_lines << line_number
          inside_ie_block = true
          stack << get_indent(line)
        elsif inside_ie_block
          match = line.match(/<haml[^>]*>([^<]+)<\/haml/)
          string = match && match[1]
          string = string ? "= #{CGI::unescapeHTML(CGI::unescapeHTML(string.strip))}\n" : "#{line.strip}\n"
          altered_lines << [line_number, string]
          indented_lines << [line_number, stack.last]
        elsif block_end?(line)
          stack << 1
          goner_lines << line_number
        elsif block_start?(line)
          stack.pop
        else
          indented_lines << [line_number, stack.last]
        end
      end

      lines = alter_lines(lines, altered_lines)
      lines = indent_lines(lines, indented_lines)
      lines = remove_lines(lines, goner_lines)

      altered_lines = []
      indented_lines = [] 
      goner_lines = []

      line_number = -1
      lines.each_cons(3) do |three_lines|
        line_number += 1
        line2_number = line_number + 1
        middle_indented_by_one = (get_indent(three_lines[1]) - get_indent(three_lines[0]) == 1)
        top_indented_more = (get_indent(three_lines[0]) >= get_indent(three_lines[2]))
        commented = (three_lines[0].to_s.strip =~ /^\//)

        if(top_indented_more && middle_indented_by_one && !commented)
          if (three_lines[1].strip =~ /^=/)
            altered_lines << [line_number, (three_lines[0].rstrip + three_lines[1].lstrip)]
          else
            altered_lines << [line_number, (three_lines[0].rstrip + " " + three_lines[1].lstrip)]
          end
          goner_lines << line2_number
        end
      end

      lines = alter_lines(lines, altered_lines)
      lines = remove_lines(lines, goner_lines)
      
      File.open(destination, "w") do |f|
        f.write(lines.join)
      end
      
      File.delete(origin)
    end
  end
end

if template_engine == "haml" || design == "compass"
  Dir["public/stylesheets/**/*.css"].each do |file|
    run "css2sass #{file} #{file.gsub(/\.css$/, '.sass')}"
    File.delete(file)
  end
end

if design == "compass"
  in_root do
    Dir["public/stylesheets/**/*.sass"].each do |file|
      run "mv #{file} app/stylesheets/#{File.basename(file)}"
    end
  end
end

# databases
rake('db:create')
rake('db:migrate')
rake('parallel:prepare[4]')
commit_state "databases set up"

# rakefile for metric_fu
rakefile 'metric_fu.rake', load_pattern('lib/tasks/metric_fu.rake')

commit_state "metric_fu setup"

# vendor rails if desired
# takes the edge of whatever branch is specified in the config file
# defaults to 2-3-stable at the moment
if rails_strategy == "vendored" || rails_strategy == "symlinked"
  if rails_strategy == "vendored"
    install_rails :branch => rails_branch
    commit_state "vendored rails"
  elsif rails_strategy == "symlinked"
    inside('vendor') do
      run("ln -s #{link_rails_root} rails")
    end
  end
  update_app
  commit_state "updated rails files from vendored copy"
end

# set up branches
branches = template_options["git_branches"]
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


# Success!
puts "SUCCESS!"
if exception_handling == "exceptional"
  puts '  Set up new app at http://getexceptional.com/apps'
  puts '  Put the right API key in config/exceptional.yml'
end
if exception_handling == "hoptoad"
  puts '  Set up new app at https://<your subdomain>.hoptoadapp.com/projects/new'
  puts '  Put the right API key in config/initializers/hoptoad.rb'
end
if monitoring == "new_relic"
  puts '  Put the right API key in config/new_relic.yml'
end
if monitoring == "scout"
  puts '  Put the right plugin ID in config/scout.yml'
  puts '  Install the scout agent gem on the production server (sudo gem install scout_agent)'
end
puts '  Put the production database password in config/database.yml'
puts '  Put mail server information in mail.rb'
puts '  Put real IP address and git repo URL in deployment files'
puts '  Add app to gitosis config'
puts "  git remote add origin git@#{capistrano_repo_host}:#{current_app_name}.git"
puts '  git push origin master:refs/heads/master'
