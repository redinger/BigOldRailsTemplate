require 'base64'
require File.join(File.expand_path(File.dirname(template), File.join(root,'..')), 'template_framework')
require File.join(File.expand_path(File.dirname(template), File.join(root,'..')), 'erb_to_haml')

init_template_framework template, root
add_template_path File.expand_path(File.join(ENV['HOME'],'.big_old_rails_template'))
load_options

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

bullet_initializer = load_snippet('bullet_initializer')
environment bullet_initializer, :env => 'development'

commit_state "Set up staging environment and hooked up Rack::Bug"

# make sure HAML files get searched if we go that route
file '.ackrc', load_pattern('.ackrc')

# jrails setup
if @javascript_library == "jquery"
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

file 'app/controllers/application_controller.rb', load_pattern('app/controllers/application_controller.rb', controller_type)
file 'app/helpers/application_helper.rb', load_pattern('app/helpers/application_helper.rb')
file 'app/helpers/layout_helper.rb', load_pattern('app/helpers/layout_helper.rb')

# initializers
initializer 'requires.rb', load_pattern('config/initializers/requires.rb')
initializer 'admin_data.rb', load_pattern('config/initializers/admin_data.rb')

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
# rake tasks to ease Heroku deployment
file 'lib/tasks/gems.rake', load_pattern('lib/tasks/gems.rake')

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
mock_require = ""
mock_include = ""
if @mocking == "rr"
  mock_require = "require 'rr'"
  mock_include = "  include RR::Adapters::TestUnit"
elsif @mocking == "mocha"
  mock_require = "require 'mocha'"
end
file 'test/test_helper.rb', load_pattern('test/test_helper.rb', 'default', binding)
file 'config/preinitializer.rb', load_pattern('config/preinitializer.rb')

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

file 'test/unit/user_session_test.rb', load_pattern('test/unit/user_session_test.rb', 'default', binding)

file 'test/unit/helpers/application_helper_test.rb', load_pattern('test/unit/helpers/application_helper_test.rb', 'default', binding)


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
if controller_type == 'default'
  if require_activation
    account_create_block = load_snippet('account_create_block', 'default_require_activation')
  else
    account_create_block = load_snippet('account_create_block')
  end
elsif controller_type == 'inherited_resources'
  if require_activation
    account_create_block = load_snippet('account_create_block', 'inherited_resources_require_activation')
  else
    account_create_block = load_snippet('account_create_block', 'inherited_resources')
  end
end

file 'app/controllers/accounts_controller.rb', load_pattern('app/controllers/accounts_controller.rb', controller_type, binding)

if require_activation
  file 'app/controllers/activations_controller.rb', load_pattern('app/controllers/activations_controller.rb', "#{controller_type}_require_activation")
end

file 'app/controllers/password_resets_controller.rb', load_pattern('app/controllers/password_resets_controller.rb', controller_type)
file 'app/controllers/user_sessions_controller.rb', load_pattern('app/controllers/user_sessions_controller.rb', controller_type)

user_create_block = ""
if controller_type == 'default'
  if require_activation
    user_create_block = load_snippet('user_create_block', 'default_require_activation')
  else
    user_create_block = load_snippet('user_create_block')
  end
elsif controller_type == 'inherited_resources'
  if require_activation
    user_create_block = load_snippet('user_create_block', 'inherited_resources_require_activation')
  else
    user_create_block = load_snippet('user_create_block', 'inherited_resources')
  end
end


file 'app/controllers/users_controller.rb' , load_pattern('app/controllers/users_controller.rb', controller_type, binding)

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

file 'app/controllers/pages_controller.rb', load_pattern('app/controllers/pages_controller.rb', controller_type, binding)

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
  erb_to_haml("app/views")
end

if template_engine == "haml" || design == "compass"
  FileUtils.mkdir("public/stylesheets/sass")
  Dir["public/stylesheets/**/*.css"].each do |file|
    sass_file = file.gsub(/\.css$/, '.sass')
    run "css2sass #{file} #{sass_file}"
    run "mv #{sass_file} public/stylesheets/sass/#{File.basename(sass_file)}"
  end
end

if design == "compass"
  in_root do
    Dir["public/stylesheets/**/*.sass"].each do |file|
      run "mv #{file} app/stylesheets/sass/#{File.basename(file)}"
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
  remove_prototype if @javascript_library != "prototype"
  commit_state "updated rails files from vendored copy"
end

# set up branches
git_branch_setup

# post-creation work
execute_post_creation_hooks

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
puts '  Create public/favicon.ico'
puts '  Put the production database password in config/database.yml'
puts '  Put mail server information in mail.rb'
puts '  Put real IP address and git repo URL in deployment files'
puts '  Add app to gitosis config'
puts "  git remote add origin git@#{capistrano_repo_host}:#{current_app_name}.git"
puts '  git push origin master:refs/heads/master'
