set :application, "#{current_app_name}"
set :repository,  "git@#{capistrano_repo_host}:#{current_app_name}.git"
set :user, "#{capistrano_user}"
set :deploy_via, :fast_remote_cache
set :copy_exclude, %w(.git doc test)
set :scm, :git

# Customize the deployment
set :tag_on_deploy, false # turn off deployment tagging, we have our own tagging strategy

set :keep_releases, 6
before "deploy", "deploy:check_revision"
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
  
namespace :deploy do
  desc "Make sure there is something to deploy"
  task :check_revision, :roles => [:web] do
    unless `git rev-parse HEAD` == `git rev-parse origin/\#{branch}`
      puts ""
      puts "  \033[1;33m**************************************************\033[0m"
      puts "  \033[1;33m* WARNING: HEAD is not the same as origin/\#{branch} *\033[0m"
      puts "  \033[1;33m**************************************************\033[0m"
      puts ""
 
      exit
    end
  end
end    
