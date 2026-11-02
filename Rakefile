require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)
task default: :spec

desc "Rewrite the dummy app's committed catalogue (spec/rails_app/config/actions.json)"
task :catalogue do
  ruby "-Ispec", "spec/write_catalogue.rb"
end
