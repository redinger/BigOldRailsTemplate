namespace :gems do
  desc "Output gems.yml and .gems in root of app (for Heroku or EngineYard)"
  task :specify => :environment do
    gems = Rails.configuration.gems
    
    # output gems.yml
    yaml = File.join(RAILS_ROOT, "gems.yml")
    File.open(yaml, "w") do |f|
      output = []
      gems.each do |gem|
        spec = { "name" => gem.name, "version" => gem.version_requirements.to_s }
        spec["install_options"] = "--source #{gem.source}" if gem.source
        output << spec
      end
      f.write output.to_yaml
      puts output.to_yaml
    end
    
    # output .gems
    dot_gems = File.join(RAILS_ROOT, ".gems")
    File.open(dot_gems, "w") do |f|
      output = []
      gems.each do |gem|
        spec = "#{gem.name} --version '#{gem.version_requirements.to_s}'"
        spec << " --source #{gem.source}" if gem.source
        output << spec
      end
      f.write output.join("\n")
      puts output.join("\n")
    end
  end
end