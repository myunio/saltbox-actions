require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/testtask"

# An app declares one authorization adapter, which every action has, so the
# specs run once for each: the whole suite with Pundit, then the examples
# tagged for ActionPolicy and for none, from the files that hold them
# (spec/rails_helper.rb).
desc "Run the specs with each authorization adapter"
task :spec do
  sh FileUtils::RUBY, "-S", "rspec"
  %w[action_policy none].each do |authorization|
    files = Dir["spec/**/*_spec.rb"].select { File.read(it).include?("authorization: :#{authorization}") }
    sh({"SALTBOX_ACTIONS_AUTHORIZATION" => authorization}, FileUtils::RUBY, "-S", "rspec", *files)
  end
end
Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end
task default: [:spec, :test]

desc "Rewrite the dummy app's committed catalog (spec/rails_app/config/actions.json)"
task :dump do
  ruby "-Ispec", "spec/write_catalog.rb"
end
