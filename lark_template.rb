require 'open-uri'
require 'yaml'
require 'base64'

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
begin
  template_options = {}
  template_paths = [
                    File.expand_path(File.join(ENV['HOME'],'.big_old_rails_template')),
                    File.expand_path(File.dirname(template), File.join(root,'..'))
                   ]

  template_paths.each do |template_path|
    template = File.join(template_path, "config.yml")
    next unless File.exists? template

    open(template) do |f|
      template_options = YAML.load(f)
    end
    # Config loaded, stop searching
    break if template_options
  end
rescue
end

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

design = template_options["design"].nil? ? ask("Which design? none (default), bluetrip").downcase : template_options["design"]
design = "none" if design.nil?

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

# Actual application generation starts here

# Delete unnecessary files
run "rm README"
run "rm public/index.html"
run "rm public/favicon.ico"

# Set up git repository
# must do before running piston or braid
git :init

# Set up gitignore and commit base state
file '.gitignore', <<-END
log/*.log
tmp/**/*
.DS\_Store
.DS_Store
db/test.sqlite3
db/development.sqlite3
/log/*.pid
/coverage/*
public/system/*
.idea/*
tmp/metric_fu/*
tmp/sent_mails/*
.ackrc
END

commit_state "base application"

# plugins
plugins = 
  {
    'admin_data' => {:options => {:git => 'git://github.com/neerajdotname/admin_data.git'}},
    'db_populate' => {:options => {:git => 'git://github.com/ffmike/db-populate.git'}},
    'exceptional' => {:options => {:git => 'git://github.com/contrast/exceptional.git'},
                      :if => 'exception_handling == "exceptional"'},
    'fast_remote_cache' => {:options => {:git => 'git://github.com/37signals/fast_remote_cache.git'}},
    'hashdown' => {:options => {:git => 'git://github.com/rubysolo/hashdown.git'}},
    'hoptoad_notifier' => {:options => {:git => 'git://github.com/thoughtbot/hoptoad_notifier.git'},
                           :if => 'exception_handling == "hoptoad"'},
    'live_validations' => {:options => {:git => 'git://github.com/augustl/live-validations.git'}},
    'new_relic' => {:options => {:git => 'git://github.com/newrelic/rpm.git'},
                    :if => 'monitoring == "new_relic"'},
    'object_daddy' => {:options => {:git => 'git://github.com/flogic/object_daddy.git'}},
    'paperclip' => {:options => {:git => 'git://github.com/thoughtbot/paperclip.git'}},
    'parallel_specs' => {:options => {:git => 'git://github.com/grosser/parallel_specs.git'}},
    'rack-bug' => {:options => {:git => 'git://github.com/brynary/rack-bug.git'}},
    'rubaidhstrano' => {:options => {:git => 'git://github.com/rubaidh/rubaidhstrano.git'}},
    'scout_rails_instrumentation' => {:options => {:git => 'git://github.com/highgroove/scout_rails_instrumentation.git'},
                                      :if => 'monitoring == "scout"'},
    'shmacros' => {:options => {:git => 'git://github.com/maxim/shmacros.git'}},
    'stringex' => {:options => {:git => 'git://github.com/rsl/stringex.git'}},
    'superdeploy' => {:options => {:git => 'git://github.com/saizai/superdeploy.git'}},
    'time-warp' => {:options => {:git => 'git://github.com/iridesco/time-warp.git'}},    
    'validation_reflection' => {:options => {:git => 'git://github.com/redinger/validation_reflection.git'}}    
  }
  
plugins.each do |name, value|
  if  value[:if].nil? || eval(value[:if])
    install_plugin name, value[:options]
  end
end
  
# gems
gem 'authlogic',
  :version => '~> 2.0'
gem 'mislav-will_paginate', 
  :version => '~> 2.2', 
  :lib => 'will_paginate',
  :source => 'http://gems.github.com'
gem 'jscruggs-metric_fu', 
  :version => '~> 1.1', 
  :lib => 'metric_fu', 
  :source => 'http://gems.github.com' 
gem "binarylogic-searchlogic",
  :lib     => 'searchlogic',
  :source  => 'http://gems.github.com',
  :version => '~> 2.0'
gem "justinfrench-formtastic", 
  :lib     => 'formtastic', 
  :source  => 'http://gems.github.com'
  
# development only
gem "cwninja-inaction_mailer", 
  :lib => 'inaction_mailer/force_load', 
  :source => 'http://gems.github.com', 
  :env => 'development'
gem "ffmike-query_trace",
  :lib => 'query_trace', 
  :source => 'http://gems.github.com',
  :env => 'development'

# test only
gem "ffmike-test_benchmark", 
  :lib => 'test_benchmark', 
  :source => 'http://gems.github.com',
  :env => 'test'
gem "webrat",
  :env => "test"

# assume gems are already on dev box, so don't install    
# rake("gems:install", :sudo => true)

commit_state "Added plugins and gems"

# environment updates
in_root do
  run 'cp config/environments/production.rb config/environments/staging.rb'
end
environment 'config.middleware.use "Rack::Bug"', :env => 'development'
environment 'config.middleware.use "Rack::Bug"', :env => 'staging'

commit_state "Set up staging environment and hooked up Rack::Bug"

# make sure HAML files get searched if we go that route
file '.ackrc', <<-END
--type-set=haml=.haml
END

# some files for app
if @javascript_library == "prototype"
  download "http://livevalidation.com/javascripts/src/1.3/livevalidation_prototype.js", "public/javascripts/livevalidation.js"
elsif @javascript_library == "jquery"
  file_from_repo "ffmike", "jquery-validate", "master", "jquery.validate.min.js", "public/javascripts/jquery.validate.min.js"
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

if design == "bluetrip"
  flash_class = "span-22 prefix-1 suffix-1 last"
end

file 'app/views/layouts/_flashes.html.erb', <<-END
<div id="flash" class="#{flash_class}">
  <% flash.each do |key, value| -%>
    <div id="flash_<%= key %>" class="<%= key %>"><%=h value %></div>
  <% end -%>
</div>
END

if @javascript_library == "prototype"
  javascript_include_tags = '<%= javascript_include_tag :defaults, "livevalidation", :cache => true %>'
elsif @javascript_library == "jquery"
  javascript_include_tags = '<%= javascript_include_tag "http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js", "http://ajax.googleapis.com/ajax/libs/jqueryui/1.7.2/jquery-ui.min.js" %><%= javascript_include_tag "jquery.validate.min.js", "application", :cache => true  %>'
end

if design == "bluetrip"
  extra_stylesheet_tags = <<-END
  <%= stylesheet_link_tag 'screen', :media => 'screen, projection', :cache => true %>
  <%= stylesheet_link_tag 'print', :media => 'print', :cache => true %>
  <!--[if IE]>
    <%= stylesheet_link_tag 'ie', :media => 'screen, projection', :cache => true %>
  <![endif]-->
  <%= stylesheet_link_tag 'style', :media => 'screen, projection', :cache => true %>
END
  footer_class = "span-24 small quiet"
end

file 'app/views/layouts/application.html.erb', <<-END
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" 
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <meta http-equiv="Content-type" content="text/html; charset=utf-8" />
    <title><%= @page_title || controller.action_name %></title>
    #{extra_stylesheet_tags}
    <%= stylesheet_link_tag 'formtastic', 'formtastic_changes', 'application', :media => 'all', :cache => true %>
    #{javascript_include_tags}
    <%= yield :head %>
  </head>
  <body>
    <div class="container">
      <%= yield :top_menu %>
      <%= render :partial => 'layouts/flashes' -%>
      <%= yield %>

      <div id="footer" class="#{footer_class}">
        Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
      </div>    
    </div>
  </body>
</html>
END

# rakefile for use with inaction_mailer
rakefile 'mail.rake', <<-END
namespace :mail do
  desc "Remove all files from tmp/sent_mails"
  task :clear do
    FileList["tmp/sent_mails/*"].each do |mail_file|
      File.delete(mail_file)
    end
  end
end
END

if design == "bluetrip"
  application_styles = <<-END

  /* @group Application Styles */

  body {
  	background-color: #ccff99;
  }

  .container {
  	background-color: white;
  }

  #top_menu {
  	text-align: right;
  }

  #left_menu ul {
  	margin: 0;
  	padding: 0;
  	list-style-type: none;
  }

  #left_menu ul a {
  	display: block;
  	width: 150px;
  	height: 20px;
  	line-height: 40px;
  	text-decoration: none;	
  }

  #left_menu li {

  }

  #footer {
  	margin-top: 15px;
  	margin-bottom: 10px;
  	text-align: center;
  }

  /* @end */
END
end

file 'public/stylesheets/application.css', <<-END
/* @group Browser Reset */

html, body {
  font-size: 12.5px; }

html, body, div, span, applet, object, iframe, h1, h2, h3, h4, h5, h6, p, blockquote, pre, a, abbr, acronym, address, big, cite, code, del, dfn, em, font, img, ins, kbd, q, s, samp, small, strike, strong, sub, sup, tt, var, dl, dt, dd, ol, ul, li, fieldset, form, label, legend, table, caption, tbody, tfoot, thead, tr, th, td {
  margin: 0;
  padding: 0;
  border: 0;
  outline: 0;
  font-family: helvetica, verdana, arial, sans-serif;
  font-style: inherit;
  font-weight: inherit;
  line-height: 1.25em;
  text-align: left;
  vertical-align: baseline; }

html {
  overflow-y: scroll; }

a img, :link img, :visited img {
  border: 0; }

strong {
  font-weight: bold; }

em {
  font-style: italic; }

table {
  border-collapse: collapse;
  border-spacing: 0; }

ul {
  list-style: none; }

  /* @end */
    
  /* @group Live Validations */

.LV_validation_message {
	font-weight: bold;
	margin-left: 5px;	
}

.LV_valid {
	background:#E6EFC2;
	color:#264409;
	border-color:#C6D880;
}

.LV_invalid {
	background:#FBE3E4;
	color:#8a1f11;
	border-color:#FBC2C4;
}

.LV_invalid_field {
	border-color: red;
	border-width: 1px;
}

  /* @end */
#{application_styles}
END

generate(:formtastic_stylesheets)

file 'app/controllers/application_controller.rb', <<-END
# Filters added to this controller apply to all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

class ApplicationController < ActionController::Base

  helper :all # include all helpers, all the time
  
  # make methods available to views
  helper_method :logged_in?, :admin_logged_in?, :current_user_session, :current_user
  
  # See ActionController::RequestForgeryProtection for details
  protect_from_forgery
  
  # See ActionController::Base for details 
  # Uncomment this to filter the contents of submitted sensitive data parameters
  # from your application log (in this case, all fields with names like "password"). 
  filter_parameter_logging :password, :confirm_password, :password_confirmation, :creditcard
  
  def logged_in?
    !current_user_session.nil?
  end
  
  def admin_required
    unless current_user && current_user.admin?
      flash[:error] = "Sorry, you don't have access to that."
      redirect_to root_url and return false
    end
  end
  
  def admin_logged_in?
    logged_in? && current_user.admin?
  end

private
  def current_user_session
    return @current_user_session if defined?(@current_user_session)
    @current_user_session = UserSession.find
  end

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = current_user_session && current_user_session.user
  end

  def require_user
    unless current_user
      store_location
      flash[:notice] = "You must be logged in to access this page"
      redirect_to new_user_session_url
      return false
    end
  end

  def require_no_user
    if current_user
      store_location
      flash[:notice] = "You must be logged out to access this page"
      redirect_to account_url
      return false
    end
  end
  
  def store_location
    session[:return_to] = request.request_uri
  end
  
  def redirect_back_or_default(default)
    redirect_to(session[:return_to] || default)
    session[:return_to] = nil
  end
end
END

file 'app/helpers/application_helper.rb', <<-END
# Methods added to this helper will be available to all templates in the application.
module ApplicationHelper
  
  # Block method that creates an area of the view that
  # is only rendered if the request is coming from an
  # anonymous user.
  def anonymous_only(&block)
    if !logged_in?
      block.call
    end
  end
  
  # Block method that creates an area of the view that
  # only renders if the request is coming from an
  # authenticated user.
  def authenticated_only(&block)
    if logged_in?
      block.call
    end
  end
  
  # Block method that creates an area of the view that
  # only renders if the request is coming from an
  # administrative user.
  def admin_only(&block)
    role_only("admin", &block)
  end

  def state_options
    [[ "Alabama", "AL" ], [ "Alaska", "AK" ], [ "Arizona", "AZ" ], [ "Arkansas", "AR" ], [ "California", "CA" ], [ "Colorado", "CO" ], [ "Connecticut", "CT" ], [ "Delaware", "DE" ], [ "District Of Columbia", "DC" ], [ "Florida", "FL" ], [ "Georgia", "GA" ], [ "Hawaii", "HI" ], [ "Idaho", "ID" ], [ "Illinois", "IL" ], [ "Indiana", "IN" ], [ "Iowa", "IA" ], [ "Kansas", "KS" ], [ "Kentucky", "KY" ], [ "Louisiana", "LA" ], [ "Maine", "ME" ], [ "Maryland", "MD" ], [ "Massachusetts", "MA" ], [ "Michigan", "MI" ], [ "Minnesota", "MN" ], [ "Mississippi", "MS" ], [ "Missouri", "MO" ], [ "Montana", "MT" ], [ "Nebraska", "NE" ], [ "Nevada", "NV" ], [ "New Hampshire", "NH" ], [ "New Jersey", "NJ" ], [ "New Mexico", "NM" ], [ "New York", "NY" ], [ "North Carolina", "NC" ], [ "North Dakota", "ND" ], [ "Ohio", "OH" ], [ "Oklahoma", "OK" ], [ "Oregon", "OR" ], [ "Pennsylvania", "PA" ], [ "Rhode Island", "RI" ], [ "South Carolina", "SC" ], [ "South Dakota", "SD" ], [ "Tennessee", "TN" ], [ "Texas", "TX" ], [ "Utah", "UT" ], [ "Vermont", "VT" ], [ "Virginia", "VA" ], [ "Washington", "WA" ], [ "West Virginia", "WV" ], [ "Wisconsin", "WI" ], [ "Wyoming", "WY" ]]
  end

  def state_options_with_blank(label = "")
    state_options.unshift([label, ""])
  end

  def full_state_name(state_abbrev)
    state_options.each do |full_name, abbrev|
      return full_name if abbrev == state_abbrev
    end
    nil
  end

private

  def role_only(rolename, &block)
    if not current_user.blank? and current_user.has_role?(rolename)
      block.call
    end
  end
  
end
END

# initializers
initializer 'requires.rb', <<-END
Dir[File.join(RAILS_ROOT, 'lib', '*.rb')].each do |f|
  require f
end
END

initializer 'admin_data.rb', <<-END
ADMIN_DATA_VIEW_AUTHORIZATION = Proc.new { |controller| controller.send("admin_logged_in?") }
ADMIN_DATA_UPDATE_AUTHORIZATION = Proc.new { |controller| return false }
END

if @javascript_library == "jquery"
  initializer 'live_validations.rb', <<-END
LiveValidations.use :jquery_validations, :default_valid_message => "", :validate_on_blur => true
END
elsif @javascript_library == "prototype"
  initializer 'live_validations.rb', <<-END
LiveValidations.use :livevalidation_dot_com, :default_valid_message => "", :validate_on_blur => true
END
end

base64_user_name = Base64.encode64(smtp_username) unless smtp_username.blank? 
base64_password = Base64.encode64(smtp_password) unless smtp_username.blank? 

initializer 'mail.rb', <<-END
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.smtp_settings = {
  :address => "#{smtp_address}",
  :port => 25,
  :domain => "#{smtp_domain}",
  :authentication => :login,
  :user_name => "#{smtp_username}",
  :password => "#{smtp_password}"  
}

# base64 encodings - useful for manual SMTP testing:
# username => #{base64_user_name}
# password => #{base64_password}
END

initializer 'date_time_formats.rb', <<-END
ActiveSupport::CoreExtensions::Time::Conversions::DATE_FORMATS.merge!(
  :us => '%m/%d/%y',
  :us_with_time => '%m/%d/%y, %l:%M %p',
  :short_day => '%e %B %Y',
  :long_day => '%A, %e %B %Y'
)

Date::DATE_FORMATS[:human] = "%B %e, %Y"
END

initializer 'query_trace.rb', <<-END
# Turn on query tracing output; requires server restart
# QueryTrace.enable!
END

initializer 'backtrace_silencers.rb', <<-END
# Be sure to restart your server when you modify this file.

# You can add backtrace silencers for libraries that you're using but don't wish to see in your backtraces.
# Rails.backtrace_cleaner.add_silencer { |line| line =~ /my_noisy_library/ }

# You can also remove all the silencers if you're trying do debug a problem that might steem from framework code.
# Rails.backtrace_cleaner.remove_silencers!

Rails.backtrace_cleaner.add_silencer { |line| line =~ /haml/ }
END

commit_state "application files and initializers"

# deployment
capify!

file 'config/deploy.rb', <<-END
set :application, "#{current_app_name}"
set :repository,  "git@#{capistrano_repo_host}:#{current_app_name}.git"
set :user, "#{capistrano_user}"
set :deploy_via, :fast_remote_cache
set :scm, :git

# Customise the deployment
set :tag_on_deploy, false # turn off deployment tagging, we have our own tagging strategy

set :keep_releases, 6
after "deploy:update", "deploy:cleanup"

# directories to preserve between deployments
# set :asset_directories, ['public/system/logos', 'public/system/uploads']

# re-linking for config files on public repos  
# namespace :deploy do
#   desc "Re-link config files"
#   task :link_config, :roles => :app do
#     run "ln -nsf \#{shared_path}/config/database.yml \#{current_path}/config/database.yml"
#   end
# end
    
END

file 'config/deploy/production.rb', <<-END
set :host, "#{capistrano_production_host}"
set :branch, "master"
END

file 'config/deploy/staging.rb', <<-END
set :host, "#{capistrano_staging_host}"
set :branch, "staging"
END

commit_state "deployment files"

# error handling
if exception_handling == "exceptional"
  file 'config/exceptional.yml', <<-END
# here are the settings that are common to all environments
common: &default_settings
  # You must specify your Exceptional API key here.
  api-key: #{exceptional_api_key}
  # Exceptional creates a separate log file from your application's logs
  # available levels are debug, info, warn, error, fatal
  log-level: info
  # The exceptional agent sends data via regular http by default
  # Setting this value to true will send data over SSL, increasing security
  # There will be an additional CPU overhead in encrypting the data, however
  # as long as your deployment environment is not Passenger (mod_rails), this
  # happens in the background so as not to incur a page wait for your users.
  ssl: false
  
development:
  <<: *default_settings
  # Normally no reason to collect exceptions in development
  # NOTE: for trial purposes you may want to enable exceptional in development
  enabled: false
  
test:
  <<: *default_settings
  # No reason to collect exceptions when running tests by default
  enabled: false

test2:
  <<: *default_settings
  # No reason to collect exceptions when running tests by default
  enabled: false

test3:
  <<: *default_settings
  # No reason to collect exceptions when running tests by default
  enabled: false

test4:
  <<: *default_settings
  # No reason to collect exceptions when running tests by default
  enabled: false

production:
  <<: *default_settings
  enabled: true

staging:
  # It's common development practice to have a staging environment that closely
  # mirrors production, by default catch errors in this environment too.
  <<: *default_settings
  enabled: true
END
end

if exception_handling == "hoptoad"
  initializer 'hoptoad.rb', <<-END
HoptoadNotifier.configure do |config|
  config.api_key = '#{hoptoad_api_key}'
end
END
end

# performance monitoring
if monitoring == "new_relic"
  file 'config/newrelic.yml', <<-END
#
# This file configures the NewRelic RPM Agent, NewRelic RPM monitors Rails 
# applications with deep visibility and low overhead.  For more information, 
# visit www.newrelic.com.
#
# This configuration file is custom generated for Lark Group Lite Account
#
# here are the settings that are common to all environments
common: &default_settings
  # ============================== LICENSE KEY ===============================
  # You must specify the licence key associated with your New Relic account.
  # This key binds your Agent's data to your account in the New Relic RPM service.
  license_key: '#{newrelic_api_key}'
  
  # Application Name
  # Set this to be the name of your application as you'd like it show up in RPM.
  # RPM will then auto-map instances of your application into a RPM "application"
  # on your home dashboard page. This setting does not prevent you from manually
  # defining applications.
  app_name: #{current_app_name}

  # the 'enabled' setting is used to turn on the NewRelic Agent.  When false,
  # your application is not instrumented and the Agent does not start up or
  # collect any data; it is a complete shut-off.
  #
  # when turned on, the agent collects performance data by inserting lightweight
  # tracers on key methods inside the rails framework and asynchronously aggregating
  # and reporting this performance data to the NewRelic RPM service at NewRelic.com.
  # below.
  enabled: false

  # The newrelic agent generates its own log file to keep its logging information
  # separate from that of your application.  Specify its log level here.
  log_level: info
  
  # The newrelic agent communicates with the RPM service via http by default.
  # If you want to communicate via https to increase security, then turn on
  # SSL by setting this value to true.  Note, this will result in increased
  # CPU overhead to perform the encryption involved in SSL communication, but this
  # work is done asynchronously to the threads that process your application code, so
  # it should not impact response times.
  ssl: false
  
  # Set your application's Apdex threshold value with the 'apdex_t' setting, in seconds. The
  # apdex_t value determines the buckets used to compute your overall Apdex score. Requests
  # that take less than apdex_t seconds to process will be classified as Satisfying transactions;
  # more than apdex_t seconds as Tolerating transactions; and more than four times the apdex_t 
  # value as Frustrating transactions. For more
  # about the Apdex standard, see http://support.newrelic.com/faqs/general/apdex
  apdex_t: 0.5

  # Proxy settings for connecting to the RPM server.
  #
  # If a proxy is used, the host setting is required.  Other settings are optional.  Default
  # port is 8080.
  #
  # proxy_host: hostname
  # proxy_port: 8080
  # proxy_user:
  # proxy_pass:

  
  # Tells transaction tracer and error collector (when enabled) whether or not to capture HTTP params. 
  # When true, the RoR filter_parameters mechanism is used so that sensitive parameters are not recorded
  capture_params: false


  # Transaction tracer captures deep information about slow
  # transactions and sends this to the RPM service once a minute. Included in the
  # transaction is the exact call sequence of the transactions including any SQL statements
  # issued.
  transaction_tracer:
  
    # Transaction tracer is enabled by default. Set this to false to turn it off. This feature
    # is only available at the Silver and above product levels.
    enabled: true
  
 
    # When transaction tracer is on, SQL statements can optionally be recorded. The recorder
    # has three modes, "off" which sends no SQL, "raw" which sends the SQL statement in its 
    # original form, and "obfuscated", which strips out numeric and string literals
    record_sql: obfuscated
    
    # Threshold in seconds for when to collect stack trace for a SQL call. In other words, 
    # when SQL statements exceed this threshold, then capture and send to RPM the current
    # stack trace. This is helpful for pinpointing where long SQL calls originate from  
    stack_trace_threshold: 0.500
  
  # Error collector captures information about uncaught exceptions and sends them to RPM for
  # viewing
  error_collector:
    
    # Error collector is enabled by default. Set this to false to turn it off. This feature
    # is only available at the Silver and above product levels
    enabled: true
    
    # Tells error collector whether or not to capture a source snippet around the place of the
    # error when errors are View related.
    capture_source: true    
    
    # To stop specific errors from reporting to RPM, set this property to comma separated 
    # values
    #
    #ignore_errors: ActionController::RoutingError, ...


# override default settings based on your application's environment

# NOTE if your application has other named environments, you should
# provide newrelic conifguration settings for these enviromnents here.

development:
  <<: *default_settings
  # turn off communication to RPM service in development mode.
  # NOTE: for initial evaluation purposes, you may want to temporarily turn
  # the agent on in development mode.
  enabled: false

  # When running in Developer Mode, the New Relic Agent will present 
  # performance information on the last 100 transactions you have 
  # executed since starting the mongrel.  to view this data, go to 
  # http://localhost:3000/newrelic
  developer: true

test:
  <<: *default_settings
  # it almost never makes sense to turn on the agent when running unit, functional or
  # integration tests or the like.
  enabled: false

test2:
  <<: *default_settings
  # it almost never makes sense to turn on the agent when running unit, functional or
  # integration tests or the like.
  enabled: false

test3:
  <<: *default_settings
  # it almost never makes sense to turn on the agent when running unit, functional or
  # integration tests or the like.
  enabled: false

test4:
  <<: *default_settings
  # it almost never makes sense to turn on the agent when running unit, functional or
  # integration tests or the like.
  enabled: false

# Turn on the agent in production for 24x7 monitoring.  NewRelic testing shows
# an average performance impact of < 5 ms per transaction, you you can leave this on
# all the time without incurring any user-visible performance degredation.
production:
  <<: *default_settings
  enabled: true

# many applications have a staging environment which behaves identically to production.
# Support for that environment is provided here.  By default, the staging environment has
# the agent turned on.
staging:
  <<: *default_settings
  enabled: true
  app_name: #{current_app_name} (Staging)
END
end

if monitoring == "scout"
  file 'config/scout.yml', <<-END
  # This is where set your Rails Instrumentation plugin id, so the instrumentation plugin 
  # can identify itself to the Scout agent.
  #
  # * You need to supply the Rails instrumentation plugin id from your account at http://scoutapp.com
  # * Typically, you will provide the plugin id for production, but not development.
  #   If you want to try out instrumentation in development, you may want to install a separate
  #   Rails Instrumentation plugin and use that plugin id for development, so your development metrics are
  #   clearly differentiated from you production metrics.

  ##########################################################################
  # Single-server setup (most common setup)
  ###########################################################################
  production: PLUGIN_ID # <-- REQUIRED: your Rails Instrumentation plugin id goes here
  development: # <-- typically you'll leave this blank


  ##########################################################################
  # Multi-server setup (advanced)
  ##########################################################################
  #production:
  #  server1.com: # <- your plugin id for server1 goes here
  #  server2.com: # <- your plugin id for server2 goes here
  #  
  #  
  #development: 
  #  server1.com: # <- plugin id for first developer's box
  #  server2.com: # <- plugin id for second developer's box
END
end

# database
if database == "mysql"
  file 'config/database.yml', <<-END  
# MySQL. Versions 4.1 and 5.0 are recommended.
#
# Install the MySQL driver:
# gem install mysql
# On Mac OS X:
# sudo gem install mysql -- --with-mysql-dir=/usr/local/mysql
# On Mac OS X Leopard:
# sudo env ARCHFLAGS="-arch i386" gem install mysql -- --with-mysql-config=/usr/local/mysql/bin/mysql_config
# This sets the ARCHFLAGS environment variable to your native architecture
# On Windows:
# gem install mysql
# Choose the win32 build.
# Install MySQL and put its /bin directory on your path.
#
# And be sure to use new-style password hashing:
# http://dev.mysql.com/doc/refman/5.0/en/old-client.html

development:
  adapter: mysql
  encoding: utf8
  reconnect: false
  database: #{current_app_name}_development
  pool: 5
  username: root
  password:
  socket: /tmp/mysql.sock

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test: &TEST
  adapter: mysql
  encoding: utf8
  reconnect: false
  database: #{current_app_name}_test<%= ENV['TEST_ENV_NUMBER'] %>
  pool: 5
  username: root
  password:
  socket: /tmp/mysql.sock

production:
  adapter: mysql
  encoding: utf8
  database: #{current_app_name}_production
  pool: 5
  username: root
  password:
  socket: /tmp/mysql.sock

staging:
  adapter: mysql
  encoding: utf8
  database: #{current_app_name}_staging
  pool: 5
  username: root
  password:
  socket: /tmp/mysql.sock

cucumber:
 <<: *TEST
END
elsif database == "sqlite"
  file 'config/database.yml', <<-END
# SQLite version 3.x
#   gem install sqlite3-ruby (not necessary on OS X Leopard)
development:
  adapter: sqlite3
  database: db/development.sqlite3
  pool: 5
  timeout: 5000

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test: &TEST
  adapter: sqlite3
  database: db/test<%= ENV['TEST_ENV_NUMBER'] %>.sqlite3
  pool: 5
  timeout: 5000

production:
  adapter: sqlite3
  database: db/production.sqlite3
  pool: 5
  timeout: 5000

staging:
  adapter: sqlite3
  database: db/staging.sqlite3
  pool: 5
  timeout: 5000

cucumber:
 <<: *TEST
END
else # database defaults to postgresql
  file 'config/database.yml', <<-END
# PostgreSQL. Versions 7.4 and 8.x are supported.
#
# Install the ruby-postgres driver:
#   gem install ruby-postgres
# On Mac OS X:
#   gem install ruby-postgres -- --include=/usr/local/pgsql
# On Windows:
#   gem install ruby-postgres
#       Choose the win32 build.
#       Install PostgreSQL and put its /bin directory on your path.
development:
  adapter: postgresql
  encoding: unicode
  database: #{current_app_name}_development
  pool: 5
  username: postgres
  password:

  # Connect on a TCP socket. Omitted by default since the client uses a
  # domain socket that doesn't need configuration. Windows does not have
  # domain sockets, so uncomment these lines.
  #host: localhost
  #port: 5432

  # Schema search path. The server defaults to $user,public
  #schema_search_path: myapp,sharedapp,public

  # Minimum log levels, in increasing order:
  #   debug5, debug4, debug3, debug2, debug1,
  #   log, notice, warning, error, fatal, and panic
  # The server defaults to notice.
  #min_messages: warning

# Warning: The database defined as "test" will be erased and
# re-generated from your development database when you run "rake".
# Do not set this db to the same as development or production.
test: &TEST
  adapter: postgresql
  encoding: unicode
  database: #{current_app_name}_test<%= ENV['TEST_ENV_NUMBER'] %>
  pool: 5
  username: postgres
  password:

production:
  adapter: postgresql
  encoding: unicode
  database: #{current_app_name}_production
  pool: 5
  username: postgres
  password: 99Schema@

staging:
  adapter: postgresql
  encoding: unicode
  database: #{current_app_name}_staging
  pool: 5
  username: postgres
  password: 99Schema@

cucumber:
 <<: *TEST
END
end

file 'db/populate/01_sample_seed.rb', <<-END
# Model.create_or_update(:id => 1, :name => 'sample')
# User db/populate/development/01_file.rb for development-only data
END

commit_state "configuration files"

# testing
file 'test/exemplars/sample_exemplar.rb', <<-END
class Company < ActiveRecord::Base
  generator_for :country => "USA"
  generator_for :organization => "Joe's Garage"
  generator_for :login, :method => :next_login
  generator_for :plan => nil
  generator_for (:currency_id) {Currency.generate.id}

  # don't worry about subscription stuff in test
  alias_method :old_valid_plan?, :valid_plan?
  def valid_plan?
    true
  end

  def self.next_login
    @last_login ||= 'joesgarage'
    @last_login.succ!
  end
end
END

file 'test/test_helper.rb', <<-END
ENV["RAILS_ENV"] = "test" if ENV["RAILS_ENV"].nil? || ENV["RAILS_ENV"] == ''
require File.expand_path(File.dirname(__FILE__) + "/../config/environment")
require 'test_help'
require 'shoulda'
require 'mocha'
require 'authlogic/test_case'
require 'webrat'

Webrat.configure do |config|
  config.mode = :rails
  config.open_error_files = false
end

# show less output on test benchmarks
# use (0,0) to suppress benchmark output entirely
Test::Unit::UI::Console::TestRunner.set_test_benchmark_limits(1,5)

# skip after_create callback during testing
class User < ActiveRecord::Base; def send_welcome_email; end; end

class ActiveSupport::TestCase
  
  self.use_transactional_fixtures = true
  self.use_instantiated_fixtures  = false

  # Setup all fixtures in test/fixtures/*.(yml|csv) for all tests in alphabetical order.
  #
  # Note: You'll currently still have to declare fixtures explicitly in integration tests
  # -- they do not yet inherit this setting
  #fixtures :all

  # Add more helper methods to be used by all tests here...
end

class ActionController::TestCase
  setup :activate_authlogic
end
END

file 'test/unit/notifier_test.rb', <<-END
require 'test_helper'

class NotifierTest < ActionMailer::TestCase
  
  should "send welcome email" do
    user = User.generate!
    Notifier.deliver_welcome_email(user)
    assert_sent_email do |email|
      email.subject = "Welcome to #{current_app_name}!"
      email.from.include?('#{notifier_email_from}')
      email.to.include?(user.email)
      email.body =~ Regexp.new(user.login)
    end
  end

  should "send password reset instructions" do
    user = User.generate!
    Notifier.deliver_password_reset_instructions(user)
    assert_sent_email do |email|
      email.subject = "Password Reset Instructions"
      email.from.include?('#{notifier_email_from}')
      email.to.include?(user.email)
      email.body =~ Regexp.new(user.perishable_token)
    end
  end
  
end
END

file 'test/unit/user_test.rb', <<-END
require 'test_helper'

class UserTest < ActiveSupport::TestCase

  context "using authlogic" do
    setup do
      activate_authlogic
    end
  
    should_be_authentic
  
    context "serialize roles" do
      setup do
        @user = User.generate
      end
    
      should "default to an empty array" do
        assert_equal [], @user.roles
      end
    
      should "allow saving and retrieving roles array" do
        @user.roles = ["soldier", "sailor", "spy"]
        @user.save
        user_id = @user.id
        user2 = User.find(user_id)
        assert_equal ["soldier", "sailor", "spy"], user2.roles
      end
    
      should "not allow non-array data" do
        assert_raise ActiveRecord::SerializationTypeMismatch do
          @user.roles = "snakeskin shoes"
          @user.save
        end
      end
    end
  
    should_callback :make_default_roles, :before_validation_on_create
    should_callback :send_welcome_email, :after_create
  
    should_allow_mass_assignment_of :login, :password, :password_confirmation, :first_name, :last_name, :email
    should_not_allow_mass_assignment_of :crypted_password, :password_salt, :persistence_token, :login_count, :last_request_at, :last_login_at,
      :current_login_at, :last_login_ip, :current_login_ip, :roles, :created_at, :updated_at, :id
  
    context "#deliver_password_reset_instructions!" do
      setup do
        @user = User.generate!
        Notifier.stubs(:deliver_password_reset_instructions)
      end
    
      should "reset the perishable token" do
        @user.expects(:reset_perishable_token!)
        @user.deliver_password_reset_instructions!
      end
    
      should "send the reset mail" do
        Notifier.expects(:deliver_password_reset_instructions).with(@user)
        @user.deliver_password_reset_instructions!
      end
    end
  
    context "#admin?" do
      setup do
        @user = User.generate
      end
    
      should "return true if the user has the admin role" do
        @user.add_role("admin")
        assert @user.admin?
      end
    
      should "return false if the user does not have the admin role" do
        @user.clear_roles
        assert !@user.admin?
      end
    end
  
    context "#has_role?" do
      setup do
        @user = User.generate
      end
    
      should "return true if the user has the specified role" do
        @user.add_role("saint")
        assert @user.has_role?("saint")
      end
    
      should "return false if the user does not have the specified role" do
        @user.clear_roles
        assert !@user.has_role?("saint")
      end
    end

    context "#add_role" do
      should "add the specified role" do
        @user = User.generate
        @user.add_role("wombat")
        assert @user.roles.include?("wombat")
      end
    end
  
    context "#remove_role" do
      should "remove the specified role" do
        @user = User.generate
        @user.add_role("omnivore")
        @user.remove_role("omnivore")
        assert !@user.roles.include?("omnivore")
      end
    end
  
    context "#clear_roles" do
      should "have no roles after clearing" do
        @user = User.generate
        @user.add_role("cat")
        @user.add_role("dog")
        @user.add_role("goldfish")
        @user.clear_roles
        assert_equal [], @user.roles
      end
    end
  
    context "#kaboom!" do
      should "blow up predictably" do
        assert_raise NameError do
          @user = User.generate!
          @user.kaboom!
        end
      end
    end
  end 
end
END

file 'test/shoulda_macros/authlogic.rb', <<-END
module Authlogic
  module ShouldaMacros
    class Test::Unit::TestCase
      def self.should_be_authentic
        klass = described_type
        should "acts as authentic" do
          assert klass.new.respond_to?(:password=)
          assert klass.new.respond_to?(:valid_password?)
        end
      end
    end
  end
end
END

file 'test/shoulda_macros/filter.rb', <<-END
class ActionController::TestCase
  def self.should_have_before_filter(expected_method, options = {})
    should_have_filter('before', expected_method, options)
  end

  def self.should_have_after_filter(expected_method, options = {})
    should_have_filter('after', expected_method, options)
  end

  def self.should_have_filter(filter_type, expected_method, options)
    description = "have \#{filter_type}_filter :\#{expected_method}"
    description << " with \#{options.inspect}" unless options.empty?

    should description do
      klass = "action_controller/filters/\#{filter_type}_filter".classify.constantize
      expected = klass.new(:filter, expected_method.to_sym, options)
      assert_equal 1, @controller.class.filter_chain.select { |filter|
        filter.method == expected.method && filter.kind == expected.kind &&
        filter.options == expected.options && filter.class == expected.class
      }.size
    end
  end
end
END

file 'test/exemplars/user_exemplar.rb', <<-END
class User < ActiveRecord::Base
  generator_for :login, :method => :next_login
  generator_for :password => 'bobby'
  generator_for :password_confirmation => 'bobby'
  generator_for :email, :method => :next_email
  
  def self.next_login
    @last_login ||= 'bobby'
    @last_login.succ!
  end
  
  def self.next_email
    @base ||= 'BobDobbs'
    @base.succ!
    "\#{@base}@example.com"
  end
  
end
END

file 'test/unit/user_session_test.rb', <<-END
require 'test_helper'

class UserSessionTest < ActiveSupport::TestCase
  # note - not an AR class
  
  should "derive from Authlogic::Session::Base" do
    Authlogic::Session::Base.controller = stub('controller')
    us = UserSession.new
    assert us.is_a?(Authlogic::Session::Base)
  end
  
end
END

file 'test/unit/helpers/application_helper_test.rb', <<-END
require 'test_helper'

class ApplicationHelperTest < ActionView::TestCase
  
  context "#anonymous_only" do
    should "call the supplied block if the current user is anonymous" do
      self.stubs(:logged_in?).returns(false)
      assert_equal "result", anonymous_only {"result"}
    end

    should "not call the supplied block if the current user is logged in" do
      self.stubs(:logged_in?).returns(true)
      assert_nil anonymous_only {"result"}
    end
  end
  
  context "#authenticated_only" do
    should "call the supplied block if the current user is logged in" do
      self.stubs(:logged_in?).returns(true)
      assert_equal "result", authenticated_only {"result"}
    end

    should "not call the supplied block if the current user is anonymous" do
      self.stubs(:logged_in?).returns(false)
      assert_nil authenticated_only {"result"}
    end
  end
  
  context "#admin_only" do
    setup do
      @current_user = User.generate
    end
    
    should "call the supplied block if the current user is logged in and an admin" do
      @current_user.add_role("admin")
      self.stubs(:current_user).returns(@current_user)
      assert_equal "result", admin_only {"result"}
    end

    should "not call the supplied block if the current user is anonymous" do
      self.stubs(:current_user).returns(nil)
      assert_nil admin_only {"result"}
    end

    should "not call the supplied block if the current user is logged in but not an admin" do
      self.stubs(:current_user).returns(@current_user)
      assert_nil admin_only {"result"}
    end
  end
  
  should "provide an array of U.S. states" do
    assert_equal [[ "Alabama", "AL" ], [ "Alaska", "AK" ], [ "Arizona", "AZ" ], [ "Arkansas", "AR" ], [ "California", "CA" ], [ "Colorado", "CO" ], [ "Connecticut", "CT" ], [ "Delaware", "DE" ], [ "District Of Columbia", "DC" ], [ "Florida", "FL" ], [ "Georgia", "GA" ], [ "Hawaii", "HI" ], [ "Idaho", "ID" ], [ "Illinois", "IL" ], [ "Indiana", "IN" ], [ "Iowa", "IA" ], [ "Kansas", "KS" ], [ "Kentucky", "KY" ], [ "Louisiana", "LA" ], [ "Maine", "ME" ], [ "Maryland", "MD" ], [ "Massachusetts", "MA" ], [ "Michigan", "MI" ], [ "Minnesota", "MN" ], [ "Mississippi", "MS" ], [ "Missouri", "MO" ], [ "Montana", "MT" ], [ "Nebraska", "NE" ], [ "Nevada", "NV" ], [ "New Hampshire", "NH" ], [ "New Jersey", "NJ" ], [ "New Mexico", "NM" ], [ "New York", "NY" ], [ "North Carolina", "NC" ], [ "North Dakota", "ND" ], [ "Ohio", "OH" ], [ "Oklahoma", "OK" ], [ "Oregon", "OR" ], [ "Pennsylvania", "PA" ], [ "Rhode Island", "RI" ], [ "South Carolina", "SC" ], [ "South Dakota", "SD" ], [ "Tennessee", "TN" ], [ "Texas", "TX" ], [ "Utah", "UT" ], [ "Vermont", "VT" ], [ "Virginia", "VA" ], [ "Washington", "WA" ], [ "West Virginia", "WV" ], [ "Wisconsin", "WI" ], [ "Wyoming", "WY" ]], state_options
  end
  
  should "provide an array of U.S. states plus blank" do
    assert_equal [["the label", ""], [ "Alabama", "AL" ], [ "Alaska", "AK" ], [ "Arizona", "AZ" ], [ "Arkansas", "AR" ], [ "California", "CA" ], [ "Colorado", "CO" ], [ "Connecticut", "CT" ], [ "Delaware", "DE" ], [ "District Of Columbia", "DC" ], [ "Florida", "FL" ], [ "Georgia", "GA" ], [ "Hawaii", "HI" ], [ "Idaho", "ID" ], [ "Illinois", "IL" ], [ "Indiana", "IN" ], [ "Iowa", "IA" ], [ "Kansas", "KS" ], [ "Kentucky", "KY" ], [ "Louisiana", "LA" ], [ "Maine", "ME" ], [ "Maryland", "MD" ], [ "Massachusetts", "MA" ], [ "Michigan", "MI" ], [ "Minnesota", "MN" ], [ "Mississippi", "MS" ], [ "Missouri", "MO" ], [ "Montana", "MT" ], [ "Nebraska", "NE" ], [ "Nevada", "NV" ], [ "New Hampshire", "NH" ], [ "New Jersey", "NJ" ], [ "New Mexico", "NM" ], [ "New York", "NY" ], [ "North Carolina", "NC" ], [ "North Dakota", "ND" ], [ "Ohio", "OH" ], [ "Oklahoma", "OK" ], [ "Oregon", "OR" ], [ "Pennsylvania", "PA" ], [ "Rhode Island", "RI" ], [ "South Carolina", "SC" ], [ "South Dakota", "SD" ], [ "Tennessee", "TN" ], [ "Texas", "TX" ], [ "Utah", "UT" ], [ "Vermont", "VT" ], [ "Virginia", "VA" ], [ "Washington", "WA" ], [ "West Virginia", "WV" ], [ "Wisconsin", "WI" ], [ "Wyoming", "WY" ]], state_options_with_blank("the label")
  end
  
  context "#full_state_name" do
    should "look up a state name" do
      assert_equal "North Carolina", full_state_name("NC")
    end
    
    should "return nil if no match" do
      assert_nil full_state_name("XX")
    end
  end
end
END

file 'test/functional/accounts_controller_test.rb', <<-END
require 'test_helper'

class AccountsControllerTest < ActionController::TestCase
  
  should_have_before_filter :require_no_user, :only => [:new, :create]
  should_have_before_filter :require_user, :only => [:show, :edit, :update]
  
  context "routing" do
    should_route :get, "/account/new", :controller => "accounts", :action => "new"
    should_route :get, "/account/edit", :action=>"edit", :controller=>"accounts"
    should_route :get, "/account", :action=>"show", :controller=>"accounts"
    should_route :put, "/account", :action=>"update", :controller=>"accounts"
    should_route :post, "/account", :action=>"create", :controller=>"accounts"
    # TODO: Figure out what to do about this
    # should_route :get, "/register", :action=>"new", :controller=>"accounts"
    
    context "named routes" do
      setup do
        get :show
      end
      
      should "generate account_path" do
        assert_equal "/account", account_path
      end
      should "generate new_account_path" do
        assert_equal "/account/new", new_account_path
      end
      should "generate edit_account_path" do
        assert_equal "/account/edit", edit_account_path
      end
      should "generate register_path" do
        assert_equal "/register", register_path
      end
    end
  end
    
  context "on GET to :new" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @the_user = User.generate!
      User.stubs(:new).returns(@the_user)
      get :new
    end
    
    should_assign_to(:user) { @the_user }
    should_assign_to(:page_title) { "Create Account" }
    should_respond_with :success
    should_render_template "users/new"
    should_not_set_the_flash
  end

  context "on POST to :create" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @the_user = User.generate!
      User.stubs(:new).returns(@the_user)
    end
    
    context "with successful creation" do
      setup do
        @the_user.stubs(:save).returns(true)
        post :create, :user => { :login => "bobby", :password => "bobby", :password_confirmation => "bobby" }
      end

      should_assign_to(:user) { @the_user }
      should_respond_with :redirect
      should_set_the_flash_to "Account registered!"
      should_redirect_to("the root url") { root_url }
    end
    
    context "with failed creation" do
      setup do
        @the_user.stubs(:save).returns(false)
        post :create, :user => { :login => "bobby", :password => "bobby", :password_confirmation => "bobby" }
      end
      
      should_assign_to(:user) { @the_user }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template "users/new"
    end
  end
  
  context "with a regular user" do
    setup do
      @the_user = User.generate!
      UserSession.create(@the_user)
    end

    context "on GET to :show" do
      setup do
        get :show
      end
    
      should_assign_to(:user) { @the_user }
      should_assign_to(:page_title) { "\#{@the_user.login} details" }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template "users/show"
    end

    context "on GET to :edit" do
      setup do
        get :edit
      end
    
      should_assign_to(:user) { @the_user }
      should_assign_to(:page_title) { "Edit \#{@the_user.login}" }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template "users/edit"
    end

    context "on PUT to :update" do
      context "with successful update" do
        setup do
          User.any_instance.stubs(:update_attributes).returns(true)
          put :update, :user => {:login => "bill" }
        end
      
        should_assign_to(:user) { @the_user }
        should_respond_with :redirect
        should_set_the_flash_to "Account updated!"
        should_redirect_to("the user's account") { account_url }
      end
    
      context "with failed update" do
        setup do
          User.any_instance.stubs(:update_attributes).returns(false)
          put :update, :user => {:login => "bill" }
        end
      
        should_assign_to(:user) { @the_user }
        should_respond_with :success
        should_not_set_the_flash
        should_render_template "users/edit"
      end
    end
  end
end
END

file 'test/functional/application_controller_test.rb', <<-END
require 'test_helper'

class ApplicationControllerTest < ActionController::TestCase
  
  # should_helper :all
  # should_have_helper_method :logged_in?, :admin_logged_in?, :current_user_session, :current_user
  # should_protect_from_forgery

  should_filter_params :password, :confirm_password, :password_confirmation, :creditcard
  
  context "#logged_in?" do
    should "return true if there is a user session" do
      @the_user = User.generate!
      UserSession.create(@the_user)
      assert controller.logged_in?
    end
    
    should "return false if there is no session" do
      assert !controller.logged_in?
    end
  end
  
  context "#admin_logged_in?" do
    should "return true if there is a user session for an admin" do
      @the_user = User.generate!
      @the_user.roles << "admin"
      UserSession.create(@the_user)
      assert controller.admin_logged_in?
    end
    
    should "return false if there is a user session for a non-admin" do
      @the_user = User.generate!
      @the_user.roles = []
      UserSession.create(@the_user)
      assert !controller.admin_logged_in?
    end
    
    should "return false if there is no session" do
      assert !controller.admin_logged_in?
    end
  end
  
  # TODO: Test filter methods
end
END

file 'test/functional/users_controller_test.rb', <<-END
require 'test_helper'

class UsersControllerTest < ActionController::TestCase
  
  should_have_before_filter :require_no_user, :only => [:new, :create]
  should_have_before_filter :require_user, :only => [:show, :edit, :update]
  should_have_before_filter :admin_required, :only => [:index, :destroy]
  
  
  context "routing" do
    should_route :get, "/users", :action=>"index", :controller=>"users"
    should_route :post, "/users", :action=>"create", :controller=>"users"
    should_route :get, "/users/new", :action=>"new", :controller=>"users"
    should_route :get, "/users/1/edit", :action=>"edit", :controller=>"users", :id => 1
    should_route :get, "/users/1", :action=>"show", :controller=>"users", :id => 1
    should_route :put, "/users/1", :action=>"update", :controller=>"users", :id => 1
    should_route :delete, "/users/1", :action=>"destroy", :controller=>"users", :id => 1
    
    context "named routes" do
      setup do
        get :index
      end
      
      should "generate users_path" do
        assert_equal "/users", users_path
      end
      should "generate user_path" do
        assert_equal "/users/1", user_path(1)
      end
      should "generate new_user_path" do
        assert_equal "/users/new", new_user_path
      end
      should "generate edit_user_path" do
        assert_equal "/users/1/edit", edit_user_path(1)
      end
    end
  end
    
  context "on GET to :index" do
    setup do
      controller.stubs(:admin_required).returns(true)
      @the_user = User.generate!
      User.stubs(:all).returns([@the_user])
      get :index
    end
    
    should_assign_to(:users) { [@the_user] }
    should_assign_to(:page_title) { "All Users" }
    should_respond_with :success
    should_render_template :index
    should_not_set_the_flash
  end
   
  context "on GET to :new" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @the_user = User.generate!
      User.stubs(:new).returns(@the_user)
      get :new
    end
    
    should_assign_to(:user) { @the_user }
    should_assign_to(:page_title) { "Create Account" }
    should_respond_with :success
    should_render_template :new
    should_not_set_the_flash
  end

  context "on POST to :create" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @the_user = User.generate!
      User.stubs(:new).returns(@the_user)
    end
    
    context "with successful creation" do
      setup do
        @the_user.stubs(:save).returns(true)
        post :create, :user => { :login => "bobby", :password => "bobby", :password_confirmation => "bobby" }
      end

      should_assign_to(:user) { @the_user }
      should_respond_with :redirect
      should_set_the_flash_to "Account registered!"
      should_redirect_to("the root url") { root_url }
    end
    
    context "with failed creation" do
      setup do
        @the_user.stubs(:save).returns(false)
        post :create, :user => { :login => "bobby", :password => "bobby", :password_confirmation => "bobby" }
      end
      
      should_assign_to(:user) { @the_user }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template :new
    end
  end
  
  context "with a regular user" do
    # TODO: insert checks that user can only get to their own stuff, even with spoofed URLs
  end
  
  context "with an admin user" do
    setup do
      @admin_user = User.generate!
      @admin_user.roles << "admin"
      UserSession.create(@admin_user)
      @the_user = User.generate!
    end

    context "on GET to :show" do
      setup do
        get :show, :id => @the_user.id
      end
    
      should_assign_to(:user) { @the_user }
      should_assign_to(:page_title) { "\#{@the_user.login} details" }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template :show
    end

    context "on GET to :edit" do
      setup do
        get :edit, :id => @the_user.id
      end
    
      should_assign_to(:user) { @the_user }
      should_assign_to(:page_title) { "Edit \#{@the_user.login}" }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template :edit
    end

    context "on PUT to :update" do
      context "with successful update" do
        setup do
          User.any_instance.stubs(:update_attributes).returns(true)
          put :update, :id => @the_user.id, :user => { :login => "bill" }
        end
      
        should_assign_to(:user) { @the_user }
        should_respond_with :redirect
        should_set_the_flash_to "Account updated!"
        should_redirect_to("the user's account") { account_url }
      end
    
      context "with failed update" do
        setup do
          User.any_instance.stubs(:update_attributes).returns(false)
          put :update, :id => @the_user.id, :user => { :login => "bill" }
        end
      
        should_assign_to(:user) { @the_user }
        should_respond_with :success
        should_not_set_the_flash
        should_render_template :edit
      end
    end
    
    context "on DELETE to :destroy" do
      setup do
        delete :destroy, :id => @the_user.id
      end

      should_respond_with :redirect
      should_set_the_flash_to "User was deleted."
      should_redirect_to("the users page") { users_path }
    end
  end
end
END

file 'test/functional/user_sessions_controller_test.rb', <<-END
require 'test_helper'

class UserSessionsControllerTest < ActionController::TestCase
  should_have_before_filter :require_no_user, :only => [:new, :create]
  should_have_before_filter :require_user, :only => :destroy

  context "routing" do
    should_route :get, "/account/new", :controller => "accounts", :action => "new"
    should_route :post, "/account", :action=>"create", :controller=>"accounts"
    should_route :delete, "/user_session", :action=>"destroy", :controller=>"user_sessions"
    # TODO: Figure out what to do about these
    # should_route :get, "/login", :action=>"new", :controller=>"user_sessions"
    # should_route :get, "/logout", :action=>"destroy", :controller=>"user_sessions"
    
    context "named routes" do
      setup do
        get :new
      end
      
      should "generate user_session_path" do
        assert_equal "/user_session", user_session_path
      end
      should "generate new_user_session_path" do
        assert_equal "/user_session/new", new_user_session_path
      end
      should "generate login_path" do
        assert_equal "/login", login_path
      end
      should "generate logout_path" do
        assert_equal "/logout", logout_path
      end
    end
  end

  context "on GET to :new" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @the_user_session = UserSession.new
      UserSession.stubs(:new).returns(@the_user_session)
      get :new
    end
    
    should_assign_to(:user_session) { @the_user_session }
    should_assign_to(:page_title) { "Login" }
    should_respond_with :success
    should_render_template :new
    should_not_set_the_flash
  end

  context "on POST to :create" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @the_user_session = UserSession.new
      UserSession.stubs(:new).returns(@the_user_session)
    end
    
    context "with successful creation" do
      setup do
        @the_user_session.stubs(:save).returns(true)
        post :create, :user_session => { :login => "bobby", :password => "bobby" }
      end

      should_assign_to(:user_session) { @the_user_session }
      should_respond_with :redirect
      should_set_the_flash_to "Login successful!"
      should_redirect_to("the root url") { root_url }
    end
    
    context "with failed creation" do
      setup do
        @the_user_session.stubs(:save).returns(false)
        post :create, :user_session => { :login => "bobby", :password => "bobby" }
      end
      
      should_assign_to(:user_session) { @the_user_session }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template :new
    end
  end
  
  context "on DELETE to :destroy" do
    setup do
      @the_user = User.generate!
      UserSession.create(@the_user)
      delete :destroy
    end
    
    should_respond_with :redirect
    should_set_the_flash_to "Logout successful!"
    should_redirect_to("the login page") { new_user_session_url }
  end
  
end
END

if ie6_blocking == 'light'
  upgrade_test = ", :upgrade => 'Your Browser is Obsolete'"
end

file 'test/functional/pages_controller_test.rb', <<-END
require 'test_helper'

class PagesControllerTest < ActionController::TestCase

  context "routing" do
    should_route :get, "/", :action=>"home", :controller=>"pages"
    should_route :get, "/pages/foo", :controller=>"pages", :action => "foo"
    
    context "named routes" do
      setup do
        get :home
      end
      
      should "generate root_path" do
        assert_equal "/", root_path
      end
    end
  end
  
  {:home => '#{current_app_name}',
   :css_test => 'CSS Test'#{upgrade_test}}.each do | page, page_title |
    context "on GET to :\#{page.to_s}" do
      setup do
        get page
      end
    
      should_assign_to(:page_title) { page_title }
      should_respond_with :success
      should_not_set_the_flash
      should_render_template page
    end
  end
  
  context "on GET to :kaboom" do
    should "blow up predictably" do
      assert_raise NameError do
        @user = User.generate!
        get :kaboom
      end
    end
  end
  
end
END

file 'test/functional/password_reset_controller_tests.rb', <<-END
require 'test_helper'

class PasswordResetsControllerTest < ActionController::TestCase

  should_have_before_filter :load_user_using_perishable_token, :only => [:edit, :update]
  
  context "routing" do
    should_route :post, "/password_resets", :action=>"create", :controller=>"password_resets"
    should_route :get, "/password_resets/new", :action=>"new", :controller=>"password_resets"
    should_route :get, "/password_resets/1/edit", :action=>"edit", :controller=>"password_resets", :id => 1
    should_route :put, "/password_resets/1", :action=>"update", :controller=>"password_resets", :id => 1
    
    context "named routes" do
      setup do
        get :new
      end
      
      should "generate new_password_reset_path" do
        assert_equal "/password_resets/new", new_password_reset_path
      end
      should "generate edit_password_reset_path" do
        assert_equal "/password_resets/1/edit", edit_password_reset_path(1)
      end
      should "generate password_reset_path" do
        assert_equal "/password_resets/1", password_reset_path(1)
      end
    end
  end
    
  context "on GET to :new" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      get :new
    end
    
    should_assign_to(:page_title) { "Forgot Password?" }
    should_respond_with :success
    should_render_template :new
    should_not_set_the_flash
  end

  context "on POST to :create" do
    setup do
      Notifier.stubs(:deliver_password_reset_instructions)
      controller.stubs(:require_no_user).returns(true)
    end

    context "with user not found" do
      setup do
        User.stubs(:find_by_email).returns(nil)
        post :create, :email => "foo@example.com"
      end

      should_respond_with :success
      should_set_the_flash_to "No user was found with that email address"
      should_render_template :new
    end
    
    context "with user found" do
      setup do
        @user = User.generate!(:email => "foo@example.com")
        post :create, :email => "foo@example.com"
      end
      
      should_respond_with :redirect
      should_set_the_flash_to "Instructions to reset your password have been emailed to you. " +
        "Please check your email."
      should_redirect_to("the home page") { root_url }
    end
  end

  context "on GET to :edit" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @user = User.generate!
      User.stubs(:find_using_perishable_token).returns(@user)
      get :edit, :id => "the token"
    end
    
    should_assign_to(:page_title) { "Select a New Password" }
    should_respond_with :success
    should_render_template :edit
    should_not_set_the_flash
  end

  context "on PUT to :update" do
    setup do
      controller.stubs(:require_no_user).returns(true)
      @user = User.generate!
      User.stubs(:find_using_perishable_token).returns(@user)
    end
    
    context "with successful save" do
      setup do
        User.any_instance.stubs(:save).returns(true)
        put :update, :id => "the token", :user => {:password => "the new password", :password_confirmation => "the new password"}
      end

      should_respond_with :redirect
      should_set_the_flash_to "Password successfully updated"
      should_redirect_to("the user's page") { account_url }
    end
    
    context "with failed save" do
      setup do
        User.any_instance.stubs(:save).returns(false)
        put :update, :id => "the token", :user => {:password => "the new password", :password_confirmation => "the new password"}
      end

      should_respond_with :success
      should_not_set_the_flash
      should_render_template :edit
    end
  end
end
END

file 'test/integration/new_user_can_register_test.rb', <<-END
require File.join(File.dirname(__FILE__), '..', 'test_helper')

class NewUserCanRegisterTest < ActionController::IntegrationTest
  context 'a site visitor' do
    
    should 'be able to create a new account' do
      visit root_path
      click_link 'Register'
      
      assert_equal new_account_path, path
      assert_contain 'Register'
      
      fill_in 'First Name', :with => "Francis"
      fill_in 'Last Name', :with => "Ferdinand"
      fill_in 'Login', :with => 'francis'
      fill_in 'Email', :with => 'francis@example.com'
      fill_in 'Password', :with => 'spambot'
      fill_in 'Password Confirmation', :with => 'spambot'
      click_button 'Register'
      
      assert_equal root_path, path
      assert_contain 'Account registered!'
    end
  end
end
END

file 'test/integration/user_can_login_test.rb', <<-END
require File.join(File.dirname(__FILE__), '..', 'test_helper')

class UserCanLoginTest < ActionController::IntegrationTest

  context 'an existing user' do
    setup do
      @user = User.generate!
    end
    
    should 'be able to login with valid id and password' do
      visit login_path
      
      fill_in 'Login', :with => @user.login
      fill_in 'Password', :with => @user.password

      click_button 'Login'

      assert_equal '/', path
      assert_contain "Login successful!"
    end
  end
end
END

file 'test/integration/user_can_logout_test.rb', <<-END
require File.join(File.dirname(__FILE__), '..', 'test_helper')

class UserCanLogoutTest < ActionController::IntegrationTest

  context 'a logged-in user' do
    setup do
      @user = User.generate!
      visit login_path
      fill_in 'Login', :with => @user.login
      fill_in 'Password', :with => @user.password
      click_button 'Login'
    end
    
    should 'be able to log out' do
      visit root_path
      
      click_link "Logout"

      assert_equal new_user_session_path, path
      assert_contain "Logout successful!"
    end
  end
end
END

commit_state "basic tests"

# authlogic setup
file 'app/controllers/accounts_controller.rb', <<-END
class AccountsController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  
  def new
    @user = User.new
    @page_title = "Create Account"
    render :template => "users/new"
  end
  
  def create
    @user = User.new(params[:user])
    if @user.save
      flash[:notice] = "Account registered!"
      redirect_back_or_default root_url
    else
      render :template => "users/new"
    end
  end
  
  def show
    find_user
    @page_title = "\#{@user.login} details"
    render :template => "users/show"
  end

  def edit
    find_user
    @page_title = "Edit \#{@user.login}"
    render :template => "users/edit"
  end
  
  def update
    find_user
    if @user.update_attributes(params[:user])
      flash[:notice] = "Account updated!"
      redirect_to account_url
    else
      render :template => "users/edit"
    end
  end

private

  def find_user
    @user = @current_user
  end
  
end
END

file 'app/controllers/password_resets_controller.rb', <<-END
class PasswordResetsController < ApplicationController
  before_filter :load_user_using_perishable_token, :only => [:edit, :update]
  
  def new
    @page_title = "Forgot Password?"
  end
  
  def create
    @user = User.find_by_email(params[:email])
    if @user
      @user.deliver_password_reset_instructions!
      flash[:notice] = "Instructions to reset your password have been emailed to you. " +
        "Please check your email."
      redirect_to root_url
    else
      flash[:notice] = "No user was found with that email address"
      render :action => :new
    end
  end
  
  def edit
    @page_title = "Select a New Password"
  end

  def update
    @user.password = params[:user][:password]
    @user.password_confirmation = params[:user][:password_confirmation]
    if @user.save
      flash[:notice] = "Password successfully updated"
      redirect_to account_url
    else
      render :action => :edit
    end
  end

  private
    def load_user_using_perishable_token
      @user = User.find_using_perishable_token(params[:id])
      unless @user
        flash[:notice] = "We're sorry, but we could not locate your account." +
          "If you are having issues try copying and pasting the URL " +
          "from your email into your browser or restarting the " +
          "reset password process."
        redirect_to root_url
      end
    end
end
END

file 'app/controllers/user_sessions_controller.rb', <<-END
class UserSessionsController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => :destroy
  
  def new
    @page_title = "Login"
    @user_session = UserSession.new
  end
  
  def create
    @user_session = UserSession.new(params[:user_session])
    if @user_session.save
      flash[:success] = "Login successful!"
      redirect_back_or_default root_url
    else
      render :action => :new
    end
  end
  
  def destroy
    current_user_session.destroy
    flash[:success] = "Logout successful!"
    redirect_back_or_default new_user_session_url
  end
end
END

file 'app/controllers/users_controller.rb', <<-END
class UsersController < ApplicationController
  before_filter :require_no_user, :only => [:new, :create]
  before_filter :require_user, :only => [:show, :edit, :update]
  before_filter :admin_required, :only => [:index, :destroy]
  
  def index
    @users = User.all
    @page_title = "All Users"
  end
  
  def new
    @user = User.new
    @page_title = "Create Account"
  end
  
  def create
    @user = User.new(params[:user])
    if @user.save
      flash[:notice] = "Account registered!"
      redirect_back_or_default root_url
    else
      render :action => :new
    end
  end
  
  def show
    find_user
    @page_title = "\#{@user.login} details"
  end

  def edit
    find_user
    @page_title = "Edit \#{@user.login}"
  end
  
  def update
    find_user
    if @user.update_attributes(params[:user])
      flash[:notice] = "Account updated!"
      redirect_to account_url
    else
      render :action => :edit
    end
  end

  def destroy
    find_user
    @user.destroy
    flash[:notice] = 'User was deleted.'
    redirect_to(users_url)  
  end

private

  def find_user
    if @current_user.admin? && params[:id]
      @user = User.find(params[:id])
    else
      @user = @current_user
    end
  end
  
end
END

file 'app/models/notifier.rb', <<-END
class Notifier < ActionMailer::Base
  default_url_options[:host] = "#{default_url_options_host}"
  
  def password_reset_instructions(user)
    setup(user)
    subject "Password Reset Instructions"
    body :edit_password_reset_url => edit_password_reset_url(user.perishable_token)
  end

  def welcome_email(user)
    setup(user)
    subject "Welcome to #{current_app_name}!"
    body :user => user
  end
  
private

  def setup(user)
    from "#{notifier_email_from}"
    sent_on Time.now
    recipients user.email
  end
  
end
END

file 'app/models/user.rb', <<-END
class User < ActiveRecord::Base
  acts_as_authentic do |c|
    c.merge_validates_format_of_login_field_options :live_validator => /^\\w[\\w\\.+\\-_@ ]+$/
    c.merge_validates_format_of_email_field_options :live_validator => "/^[A-Z0-9_\\.%\\+\\-]+@(?:[A-Z0-9\\-]+\\.)+(?:[A-Z]{2,4}|museum|travel)$/i"
  end
  
  serialize :roles, Array
  
  before_validation_on_create :make_default_roles
  after_create :send_welcome_email
  
  attr_accessible :login, :password, :password_confirmation, :email, :first_name, :last_name
  
  def deliver_password_reset_instructions!
    reset_perishable_token!
    Notifier.deliver_password_reset_instructions(self)
  end
  
  def admin?
    has_role?("admin")
  end
  
  def has_role?(role)
    roles.include?(role)
  end
     
  def add_role(role)
    self.roles << role
  end
     
  def remove_role(role)
    self.roles.delete(role)
  end
  
  def clear_roles
    self.roles = []
  end
  
  def kaboom!
    r = RegExp.new("foo")
  end

private
  def make_default_roles
    clear_roles if roles.nil?
  end
  
  def send_welcome_email
    Notifier.deliver_welcome_email(self)
  end
end
END

file 'app/models/user_session.rb', <<-END
class UserSession < Authlogic::Session::Base
end
END

file 'app/views/notifier/password_reset_instructions.html.erb', <<-END
A request to reset your password has been made. If you did not make this request, simply ignore this email. If you did make this request just click the link below:

<%= @edit_password_reset_url %>

If the above URL does not work try copying and pasting it into your browser. If you continue to have problem please feel free to contact us.
END

file 'app/views/notifier/welcome_email.html.erb', <<-END
Welcome to #{current_app_name}!

Thank you for creating an account at #{current_app_name}.

Your login is <%= @user.login %>. You can log in to the site at <%= login_url %> .

If you forget your password, you can visit <%= new_password_reset_url %> to reset it.
END

file 'app/views/password_resets/edit.html.erb', <<-END
<h1>Change My Password</h1>

<% semantic_form_for @user, :url => password_reset_path, :method => :put, :live_validations => true do |f| %>
  <%= f.error_messages %>
  <%= f.input :password, :password_confirmation %>
  <%= f.commit_button "Update my password and log me in" %>
<% end %>
END

file 'app/views/password_resets/new.html.erb', <<-END
<h1>Reset Password</h1>

Fill out the form below and instructions to reset your password will be emailed to you:<br />
<br />

<% form_tag password_resets_path do %>
  <label>Email:</label><br />
  <%= text_field_tag "email" %><br />
  <br />
  <%= submit_tag "Reset my password" %>
<% end %>
END

if design == "bluetrip"
  file 'app/views/user_sessions/new.html.erb', <<-END
<div id="main_without_left_menu" class="span-22 prefix-1 suffix-1 last">

  <h1>Login</h1>

  <% semantic_form_for @user_session, :url => user_session_path do |f| %>
    <%= f.error_messages %>
    <%= f.inputs :login, :password %>
    <%= f.check_box :remember_me %>
    Remember Me <%= f.commit_button "Login" %>
  <% end %>
  <%= link_to "Register", register_path %>
</div>
END
else
  file 'app/views/user_sessions/new.html.erb', <<-END
<h1>Login</h1>

<% semantic_form_for @user_session, :url => user_session_path do |f| %>
  <%= f.error_messages %>
  <%= f.inputs :login, :password %>
  <%= f.check_box :remember_me %>
  Remember Me <%= f.commit_button "Login" %>
<% end %>
<%= link_to "Register", register_path %>
END
end

file 'app/views/users/index.html.erb', <<-END
<h1>Listing users</h1>

<table>
  <tr>
    <th>Login</th>
    <th colspan="3"></th>
  </tr>

<% @users.each do |user| %>
  <tr>
    <td><%=h user.login %></td>
    <td><%= link_to 'Show', user %></td>
    <td><%= link_to 'Edit', edit_user_path(user) %></td>
    <td><%= link_to 'Destroy', user, :confirm => 'Are you sure?', :method => :delete %></td>
  </tr>
<% end %>
</table>

<br />

<%= link_to 'New user', new_user_path %>
END

file 'app/views/users/_form.html.erb', <<-END
<%= form.inputs :first_name, :last_name, :login, :email %>
<br />
<% if form.object.new_record? %>
  <%= form.inputs :password, :password_confirmation %>
<% end %>
END

if design == "bluetrip" 
  file 'app/views/users/edit.html.erb', <<-END
  <div id="main_without_left_menu" class="span-22 prefix-1 suffix-1 last">

    <h1>Edit My Account</h1>

    <% semantic_form_for @user, :url => account_path, :live_validations => true do |f| %>
      <%= f.error_messages %>
      <%= render :partial => "users/form", :object => f %>
      <%= f.commit_button "Update"%>
    <% end %>

    <br /><%= link_to "My Profile", account_path %>
  </div>
END
else
  file 'app/views/users/edit.html.erb', <<-END
  <h1>Edit My Account</h1>

  <% semantic_form_for @user, :url => account_path, :live_validations => true do |f| %>
    <%= f.error_messages %>
    <%= render :partial => "users/form", :object => f %>
    <%= f.commit_button "Update"%>
  <% end %>

  <br /><%= link_to "My Profile", account_path %>
  END
end

if design == "bluetrip"
  file 'app/views/users/new.html.erb', <<-END
<div id="main_without_left_menu" class="span-22 prefix-1 suffix-1 last">

  <h1>Register</h1>

  <% semantic_form_for @user, :url => account_path, :live_validations => true do |f| %>
    <%= f.error_messages %>
    <%= render :partial => "users/form", :object => f %>
    <% f.buttons do %>
    <%= f.commit_button "Register" %>
    <% end %>
  <% end %>

</div>
END
else
  file 'app/views/users/new.html.erb', <<-END
<h1>Register</h1>

<% semantic_form_for @user, :url => account_path, :live_validations => true do |f| %>
  <%= f.error_messages %>
  <%= render :partial => "users/form", :object => f %>
  <%= f.commit_button "Register" %>
<% end %>
END
end

file 'app/views/users/show.html.erb', <<-END
<p>
  <b>Login:</b>
  <%=h @user.login %>
</p>

<p>
  <b>Email:</b>
  <%=h @user.email %>
</p>

<% admin_only do %>
  <p>
    <b>Login count:</b>
    <%=h @user.login_count %>
  </p>

  <p>
    <b>Last request at:</b>
    <%=h @user.last_request_at %>
  </p>

  <p>
    <b>Last login at:</b>
    <%=h @user.last_login_at %>
  </p>

  <p>
    <b>Current login at:</b>
    <%=h @user.current_login_at %>
  </p>

  <p>
    <b>Last login ip:</b>
    <%=h @user.last_login_ip %>
  </p>

  <p>
    <b>Current login ip:</b>
    <%=h @user.current_login_ip %>
  </p>
<% end %>

<%= link_to 'Edit', edit_account_path %>
END

file 'db/migrate/01_create_users.rb', <<-END
class CreateUsers < ActiveRecord::Migration
  def self.up
    create_table :users do |t|
      t.timestamps
      t.string :login, :null => false
      t.string :crypted_password, :null => false
      t.string :password_salt, :null => false
      t.string :persistence_token, :null => false
      t.integer :login_count, :default => 0, :null => false
      t.datetime :last_request_at
      t.datetime :last_login_at
      t.datetime :current_login_at
      t.string :last_login_ip
      t.string :current_login_ip
      t.string :roles
      t.string :first_name
      t.string :last_name
      t.string :perishable_token, :default => "", :null => false
      t.string :email, :default => "", :null => false
    end
    
    add_index :users, :login
    add_index :users, :persistence_token
    add_index :users, :last_request_at
    add_index :users, :perishable_token
    add_index :users, :email
  end

  def self.down
    drop_table :users
  end
end
END

file 'db/migrate/02_create_sessions.rb', <<-END
class CreateSessions < ActiveRecord::Migration
  def self.up
    create_table :sessions do |t|
      t.string :session_id, :null => false
      t.text :data
      t.timestamps
    end

    add_index :sessions, :session_id
    add_index :sessions, :updated_at
  end

  def self.down
    drop_table :sessions
  end
end
END

commit_state "basic Authlogic setup"

# static pages
if ie6_blocking == "light"
  ie6_method = <<-END
  def upgrade
    @page_title = "Your Browser is Obsolete"
  end
END
end

file 'app/controllers/pages_controller.rb', <<-END
class PagesController < ApplicationController
  
  def home
    @page_title = '#{current_app_name}'
  end
  
  def css_test
    @page_title = "CSS Test"
  end
  
  def kaboom
    User.first.kaboom!
  end
  
#{ie6_method if ie6_blocking == 'light'}  
end
END

if ie6_blocking == "light"
  ie6_warning = <<-END
  <!--[if lt IE 7]>
	<p class="flash_error">
		Your browser is obsolete. For best results in #{current_app_name}, please <%= link_to "Upgrade", pages_path(:action => 'upgrade'), :target => :blank %>
	</p>
  <![endif]-->
END
elsif ie6_blocking == "ie6nomore"
  ie6_warning = <<-END
  <!--[if lt IE 7]>
  <div style='border: 1px solid #F7941D; background: #FEEFDA; text-align: center; clear: both; height: 75px; position: relative;'>
    <div style='position: absolute; right: 3px; top: 3px; font-family: courier new; font-weight: bold;'><a href='#' onclick='javascript:this.parentNode.parentNode.style.display="none"; return false;'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-cornerx.jpg' style='border: none;' alt='Close this notice'/></a></div>
    <div style='width: 640px; margin: 0 auto; text-align: left; padding: 0; overflow: hidden; color: black;'>
      <div style='width: 75px; float: left;'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-warning.jpg' alt='Warning!'/></div>
      <div style='width: 275px; float: left; font-family: Arial, sans-serif;'>
        <div style='font-size: 14px; font-weight: bold; margin-top: 12px;'>You are using an outdated browser</div>
        <div style='font-size: 12px; margin-top: 6px; line-height: 12px;'>For a better experience using this site, please upgrade to a modern web browser.</div>
      </div>
      <div style='width: 75px; float: left;'><a href='http://www.firefox.com' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-firefox.jpg' style='border: none;' alt='Get Firefox 3.5'/></a></div>
      <div style='width: 75px; float: left;'><a href='http://www.browserforthebetter.com/download.html' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-ie8.jpg' style='border: none;' alt='Get Internet Explorer 8'/></a></div>
      <div style='width: 73px; float: left;'><a href='http://www.apple.com/safari/download/' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-safari.jpg' style='border: none;' alt='Get Safari 4'/></a></div>
      <div style='float: left;'><a href='http://www.google.com/chrome' target='_blank'><img src='http://www.ie6nomore.com/files/theme/ie6nomore-chrome.jpg' style='border: none;' alt='Get Google Chrome'/></a></div>
    </div>
  </div>
  <![endif]-->
END
end

if design == "bluetrip"
  top_menu_class = "span-24"
  left_menu_class = "span-5 suffix-1"
  main_with_left_menu_class = "span-17 suffix-1 last"
end

file 'app/views/pages/home.html.erb', <<-END
<% content_for :top_menu do %>
  <div id="top_menu" class="#{top_menu_class}">
    <% anonymous_only do %>
      <%= link_to "Register", new_account_path %>
      <%= link_to "Login", new_user_session_path %>
    <% end %>
    <% authenticated_only do %>
      <%= link_to "Logout", user_session_path, :method => :delete, :confirm => "Are you sure you want to logout?" %>
      <%= link_to "Your Account", account_path %>
    <% end %>
  </div>
<% end %>

<div id="main_wrapper">
  <div id="left_menu" class="#{left_menu_class}">
    <ul>
    <% anonymous_only do %>
      <li><%= link_to "Register", new_account_path %></li>
      <li><%= link_to "Login", new_user_session_path %></li>
    <% end %>
    <% authenticated_only do %>
      <li><%= link_to "App menu item", "#" %></li>
      <li><%= link_to "App menu item", "#" %></li>
      <li><%= link_to "App menu item", "#" %></li>
    <% end %>
    </ul>
  </div>

  <div id="main_with_left_menu" class="#{main_with_left_menu_class}">
    <h1>Welcome to #{current_app_name}</h1>
      <!--[if lt IE 7]>
  	<p class="flash_error">
  		Your browser is obsolete. For best results in #{current_app_name}, please <%= link_to "Upgrade", pages_path(:action => 'upgrade'), :target => :blank %>
  	</p>
    <![endif]-->

    <p>Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
  </div>
</div>
END

file 'app/views/pages/css_test.html.erb', <<-END
<!-- Sample Content to Plugin to Template -->
<h1>CSS Basic Elements</h1>

<p>The purpose of this HTML is to help determine what default settings are with CSS and to make sure that all possible HTML Elements are included in this HTML so as to not miss any possible Elements when designing a site.</p>

<hr />

<h1 id="headings">Headings</h1>

<h1>Heading 1</h1>
<h2>Heading 2</h2>
<h3>Heading 3</h3>
<h4>Heading 4</h4>
<h5>Heading 5</h5>
<h6>Heading 6</h6>

<small><a href="#wrapper">[top]</a></small>
<hr />


<h1 id="paragraph">Paragraph</h1>

<img style="width:250px;height:125px;float:right" src="images/css_gods_language.png" alt="CSS | God's Language" />
<p>Lorem ipsum dolor sit amet, <a href="#" title="test link">test link</a> adipiscing elit. Nullam dignissim convallis est. Quisque aliquam. Donec faucibus. Nunc iaculis suscipit dui. Nam sit amet sem. Aliquam libero nisi, imperdiet at, tincidunt nec, gravida vehicula, nisl. Praesent mattis, massa quis luctus fermentum, turpis mi volutpat justo, eu volutpat enim diam eget metus. Maecenas ornare tortor. Donec sed tellus eget sapien fringilla nonummy. Mauris a ante. Suspendisse quam sem, consequat at, commodo vitae, feugiat in, nunc. Morbi imperdiet augue quis tellus.</p>

<p>Lorem ipsum dolor sit amet, <em>emphasis</em> consectetuer adipiscing elit. Nullam dignissim convallis est. Quisque aliquam. Donec faucibus. Nunc iaculis suscipit dui. Nam sit amet sem. Aliquam libero nisi, imperdiet at, tincidunt nec, gravida vehicula, nisl. Praesent mattis, massa quis luctus fermentum, turpis mi volutpat justo, eu volutpat enim diam eget metus. Maecenas ornare tortor. Donec sed tellus eget sapien fringilla nonummy. Mauris a ante. Suspendisse quam sem, consequat at, commodo vitae, feugiat in, nunc. Morbi imperdiet augue quis tellus.</p>

<small><a href="#wrapper">[top]</a></small>
<hr />

<h1 id="list_types">List Types</h1>

<h3>Definition List</h3>
<dl>
	<dt>Definition List Title</dt>
	<dd>This is a definition list division.</dd>
</dl>

<h3>Ordered List</h3>
<ol>
	<li>List Item 1</li>
	<li>List Item 2</li>
	<li>List Item 3</li>
</ol>

<h3>Unordered List</h3>
<ul>
	<li>List Item 1</li>
	<li>List Item 2</li>
	<li>List Item 3</li>
</ul>

<small><a href="#wrapper">[top]</a></small>
<hr />

<h1 id="form_elements">Fieldsets, Legends, and Form Elements</h1>

<fieldset>
	<legend>Legend</legend>
	
	<p>Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Nullam dignissim convallis est. Quisque aliquam. Donec faucibus. Nunc iaculis suscipit dui. Nam sit amet sem. Aliquam libero nisi, imperdiet at, tincidunt nec, gravida vehicula, nisl. Praesent mattis, massa quis luctus fermentum, turpis mi volutpat justo, eu volutpat enim diam eget metus.</p>
	
	<form>
		<h2>Form Element</h2>
		
		<p>Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Nullam dignissim convallis est. Quisque aliquam. Donec faucibus. Nunc iaculis suscipit dui.</p>
		
		<p><label for="text_field">Text Field:</label><br />
		<input type="text" id="text_field" /></p>
		
		<p><label for="text_area">Text Area:</label><br />
		<textarea id="text_area"></textarea></p>
		
		<p><label for="select_element">Select Element:</label><br />
			<select name="select_element">
			<optgroup label="Option Group 1">
				<option value="1">Option 1</option>
				<option value="2">Option 2</option>
				<option value="3">Option 3</option>
			</optgroup>
			<optgroup label="Option Group 2">
				<option value="1">Option 1</option>
				<option value="2">Option 2</option>
				<option value="3">Option 3</option>
			</optgroup>
		</select></p>
		
		<p><label for="radio_buttons">Radio Buttons:</label><br />
			<input type="radio" class="radio" name="radio_button" value="radio_1" /> Radio 1<br/>
				<input type="radio" class="radio" name="radio_button" value="radio_2" /> Radio 2<br/>
				<input type="radio" class="radio" name="radio_button" value="radio_3" /> Radio 3<br/>
		</p>
		
		<p><label for="checkboxes">Checkboxes:</label><br />
			<input type="checkbox" class="checkbox" name="checkboxes" value="check_1" /> Radio 1<br/>
				<input type="checkbox" class="checkbox" name="checkboxes" value="check_2" /> Radio 2<br/>
				<input type="checkbox" class="checkbox" name="checkboxes" value="check_3" /> Radio 3<br/>
		</p>
		
		<p><label for="password">Password:</label><br />
			<input type="password" class="password" name="password" />
		</p>
		
		<p><label for="file">File Input:</label><br />
			<input type="file" class="file" name="file" />
		</p>
		
		
		<p><input class="button" type="reset" value="Clear" /> <input class="button" type="submit" value="Submit" />
		</p>
		

		
	</form>
	
</fieldset>

<small><a href="#wrapper">[top]</a></small>
<hr />

<h1 id="tables">Tables</h1>

<table cellspacing="0" cellpadding="0">
	<tr>
		<th>Table Header 1</th><th>Table Header 2</th><th>Table Header 3</th>
	</tr>
	<tr>
		<td>Division 1</td><td>Division 2</td><td>Division 3</td>
	</tr>
	<tr class="even">
		<td>Division 1</td><td>Division 2</td><td>Division 3</td>
	</tr>
	<tr>
		<td>Division 1</td><td>Division 2</td><td>Division 3</td>
	</tr>

</table>

<small><a href="#wrapper">[top]</a></small>
<hr />

<h1 id="misc">Misc Stuff - abbr, acronym, pre, code, sub, sup, etc.</h1>

<p>Lorem <sup>superscript</sup> dolor <sub>subscript</sub> amet, consectetuer adipiscing elit. Nullam dignissim convallis est. Quisque aliquam. <cite>cite</cite>. Nunc iaculis suscipit dui. Nam sit amet sem. Aliquam libero nisi, imperdiet at, tincidunt nec, gravida vehicula, nisl. Praesent mattis, massa quis luctus fermentum, turpis mi volutpat justo, eu volutpat enim diam eget metus. Maecenas ornare tortor. Donec sed tellus eget sapien fringilla nonummy. <acronym title="National Basketball Association">NBA</acronym> Mauris a ante. Suspendisse quam sem, consequat at, commodo vitae, feugiat in, nunc. Morbi imperdiet augue quis tellus.  <abbr title="Avenue">AVE</abbr></p>

<pre><p>Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Nullam dignissim convallis est. Quisque aliquam. Donec faucibus. Nunc iaculis suscipit dui. Nam sit amet sem. Aliquam libero nisi, imperdiet at, tincidunt nec, gravida vehicula, nisl. Praesent mattis, massa quis luctus fermentum, turpis mi volutpat justo, eu volutpat enim diam eget metus. Maecenas ornare tortor. Donec sed tellus eget sapien fringilla nonummy. <acronym title="National Basketball Association">NBA</acronym> Mauris a ante. Suspendisse quam sem, consequat at, commodo vitae, feugiat in, nunc. Morbi imperdiet augue quis tellus.  <abbr title="Avenue">AVE</abbr></p></pre>

<blockquote>
	"This stylesheet is going to help so freaking much." <br />-Blockquote
</blockquote>

<small><a href="#wrapper">[top]</a></small>
<!-- End of Sample Content -->
END

if ie6_blocking == 'light'
file 'app/views/pages/upgrade.html.erb', <<-END
<div id="ie6msg">
<h4>#{current_app_name} works best with a newer browser than you are using.</h4>
<p>To get the best possible experience using #{current_app_name}, we recommend that you upgrade your browser to a newer version. The current version is <a href="http://www.microsoft.com/windows/downloads/ie/getitnow.mspx" target="_blank">Internet Explorer 7</a> or <a href="http://www.microsoft.com/windows/internet-explorer/default.aspx target="_blank"">Internet Explorer 8</a>. The upgrade is free. If you’re using a PC at work you should contact your IT-administrator. Either way, we'd like to encourage you to stop using IE6 and try a more secure and Web Standards-friendly browser.</p>
<p>#{current_app_name} also supports other popular browsers like <strong><a href="http://getfirefox.com" target="_blank">Firefox</a></strong> or <strong><a href="http://www.opera.com" target="_blank">Opera</a></strong>.</p>
</div>
END
end

file 'doc/README_FOR_APP', <<-END
TODO after installing:

#{"- Set up new app at http://getexceptional.com/apps" if exception_handling == 'exceptional'}
#{"- Put the right API key in config/exceptional.yml" if exception_handling == 'exceptional'}
#{"- Set up new app at http://www.hoptoadapp.com/" if exception_handling == 'hoptoad'}
#{"- Put the right API key in config/initializers/hoptoad.rb" if exception_handling == 'hoptoad'}
#{"- Put the right API key in config/new_relic.yml" if monitoring == 'new_relic'}
#{"- Put the right plugin ID in config/scout.yml" if monitoring == 'scout'}
#{"- Install the scout agent gem on the production server (sudo gem install scout_agent)" if monitoring == 'scout'}
- Put the production database password in config/database.yml
- Put mail server information in mail.rb
- Put real IP address and git repo URL in deployment files
- Add app to gitosis config
- git remote add origin git@#{capistrano_repo_host}:#{current_app_name}.git
- git push origin master:refs/heads/master

This application includes:

Design Tools
============
- Forms are built using formtastic for added DRYness
#{" - Bluetrip CSS for visual design" if design == 'bluetrip'}
- live-validations for client-side JavaScript data entry validation. Add :live_validations => true to form_for declarations to hook this up.

Coding Tools
============
- Authlogic for user authentication, including password resets, 
    anonymous_only, authenticated_only, admin_only application helpers
- World's simplest authorization system: manage multiple string roles on users with User#add_role, User#remove_role, User#clear_roles, and User#has_role?
- Date formats: :us, :us_with_time, :short_day, :long_day
- Paperclip for attachment management
- /pages/css_test will show most CSS styles in action
- Searchlogic for magic named scopes and search forms - http://rdoc.info/projects/binarylogic/searchlogic
    attribute_equals, attribute_does_not_equal, attribute_begins_with, attribute_like, attribute_ends_with, attribute_greater_than,
    attribute_null, attribute_blank etc. etc.
- Stringex for extra string functionality
    acts_as_url, String#to_ascii, String#to_html, String#to_url, String#remove_formatting, String.random
- US State application helpers
- will-paginate for pagination
#{"- jQuery and jQueryUI from Google APIs" if @javascript_library == "jquery"}


Database Tools
==============
- Hooked up for #{"PostgreSQL" if database == 'postgresql'}#{"MySQL" if database == 'mysql'}#{"sqlite 3" if database == 'sqlite'}
- admin-data plugin for administrative UI. http://localhost:3000/admin_data will get you to the application's data. On production,
  only admin can view data, no one can edit (modify config/initializers/admin_data.rb to adjust this)
- db-populate for seed data


Deployment Tools
================
- fast_remote_cache strategy for deployment
- rubiadhstrano for deployment recipes
    automatically uses multiple targets, so: cap production deploy for deployment to production
- superdeploy for additional Capistrano tasks. cap -T for full list.


External Services
=================
- #{"Exceptional" if exception_handling == "exceptional"}#{"Hoptoad" if exception_handling == "hoptoad"} for error tracking. Go to /pages/kaboom to test after finishing #{"Exceptional" if exception_handling == "exceptional"}#{"Hoptoad" if exception_handling == "hoptoad"} setup.
#{"- New Relic for performance tracking" if monitoring == 'new_relic'} 
#{"- Scout for performance tracking" if monitoring == 'scout'} 


Testing Tools
=============
- Shoulda and Test::Unit for testing
- Mocha for mocking
- Object Daddy for factories
- Generated code is already covered by tests
- parallel-specs for faster testing. 
    rake parallel:prepare[2] to set up two test databases (already done)
    rake test:parallel[2] to distribute tests across two cores
    rake -T parallel to see more - RSpec and Cucumber are also supported
- rack-bug for request/response/perf analysis. http://localhost:3000/__rack_bug__/bookmarklet.html to add bookmarklet to browser.
- shmacros for additional Shoulda macros
    should_accept_nested_attributes_for, should_act_as_taggable_on, should_callback, should_delegate, more
- More extra shoulda macros:
    should_have_before_filter, should_have_after_filter
- metric-fu for static code analysis. rake metrics:all, configure in Rakefile
- inaction-mailer is installed for development environment, so mails sent during dev will end up as files in /tmp/sent_mails
  Get rid of all sent mail files with rake mail:clear
- time-warp for forcing time in tests (use pretend_now_is)
- test_benchmark to identify slow tests (in test environment only)
- query-trace to locate source of queries in the log (development only - turn on via config/initializers/query_trace.rb)
END

commit_state "static pages"

# simple default routing
file 'config/routes.rb', <<-END
ActionController::Routing::Routes.draw do |map|
  map.resource :account, :except => :destroy
  map.resources :password_resets, :only => [:new, :create, :edit, :update]
  map.resources :users
  map.resource :user_session, :only => [:new, :create, :destroy]
  map.login 'login', :controller => "user_sessions", :action => "new"
  map.logout 'logout', :controller => "user_sessions", :action => "destroy"
  map.register 'register', :controller => "accounts", :action => "new"
  map.root :controller => "pages", :action => "home"
  map.pages 'pages/:action', :controller => "pages"
end
END

commit_state "routing"

# databases
rake('db:create')
rake('db:migrate')
rake('parallel:prepare[4]')
commit_state "databases set up"

# rakefile for metric_fu
rakefile 'metric_fu.rake', <<-END
require 'metric_fu'
MetricFu::Configuration.run do |config|
  # not doing saikuro at the moment 
  config.metrics  = [:churn, :stats, :flog, :flay, :reek, :roodi, :rcov]
  config.rcov[:rcov_opts] << "-Itest"
  # config.flay     = { :dirs_to_flay => ['app', 'lib']  } 
  # config.flog     = { :dirs_to_flog => ['app', 'lib']  }
  # config.reek     = { :dirs_to_reek => ['app', 'lib']  }
  # config.roodi    = { :dirs_to_roodi => ['app', 'lib'] }
  # config.saikuro  = { :output_directory => 'scratch_directory/saikuro', 
  #                     :input_directory => ['app', 'lib'],
  #                     :cyclo => "",
  #                     :filter_cyclo => "0",
  #                     :warn_cyclo => "5",
  #                     :error_cyclo => "7",
  #                     :formater => "text"} #this needs to be set to "text"
  # config.churn    = { :start_date => "1 year ago", :minimum_churn_count => 10}
  # config.rcov     = { :test_files => ['test/**/*_test.rb', 
  #                                     'spec/**/*_spec.rb'],
  #                     :rcov_opts => ["--sort coverage", 
  #                                    "--no-html", 
  #                                    "--text-coverage",
  #                                    "--no-color",
  #                                    "--profile",
  #                                    "--rails",
  #                                    "--exclude /gems/,/Library/,spec"]}
end
END

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
