require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/testtask"

RSpec::Core::RakeTask.new(:spec)
Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end
task default: [:spec, :test]

desc "Rewrite the dummy app's committed catalog (spec/rails_app/config/actions.json)"
task :dump do
  ruby "-Ispec", "spec/write_catalog.rb"
end
