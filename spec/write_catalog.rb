# Rewrites the dummy app's committed catalog: bundle exec rake dump
require "rspec/core"
require_relative "rails_helper"
Saltbox::Actions::Registry.catalog_path.write(Saltbox::Actions::Registry.catalog_json)
puts "Wrote #{Saltbox::Actions::Registry.actions.size} actions"
