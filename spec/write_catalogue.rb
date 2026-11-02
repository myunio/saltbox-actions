# Rewrites the dummy app's committed catalogue: bundle exec rake catalogue
require "rspec/core"
require_relative "rails_helper"
Saltbox::Actions::Registry.catalogue_path.write(Saltbox::Actions::Registry.catalogue_json)
puts "Wrote #{Saltbox::Actions::Registry.actions.size} actions"
