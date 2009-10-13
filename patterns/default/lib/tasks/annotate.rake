# Based on tasks in ctran-annotate; copied here to make available when annotate is
# installed as a gem, and then namespaced
namespace :annotate do
  desc "Add schema information (as comments) to model and fixture files"
  task :models => :environment do
    require 'annotate/annotate_models'
    options={}
    options[:position_in_class] = ENV['position_in_class'] || ENV['position'] || :after
    options[:position_in_fixture] = ENV['position_in_fixture'] || ENV['position']  || :after
    options[:show_indexes] = ENV['show_indexes'] || true
    options[:model_dir] = ENV['model_dir']
    options[:include_version] = ENV['include_version']
    AnnotateModels.do_annotations(options)
  end

  desc "Remove schema information from model and fixture files"
  task :remove => :environment do
    require 'annotate/annotate_models'
    options={}
    options[:model_dir] = ENV['model_dir']
    AnnotateModels.remove_annotations(options)
  end

  desc "Prepends the route map to the top of routes.rb"
  task :routes do
    require 'annotate/annotate_routes'
    AnnotateRoutes.do_annotate
  end
end

namespace :db do
  desc "Run migrations, run populations, and annotate"
  task :migrate_plus => [ 'db:migrate', 'db:populate', 'annotate:models']
end