# frozen_string_literal: true

require_relative "lib/saltbox/actions/version"

Gem::Specification.new do |spec|
  spec.name = "saltbox-actions"
  spec.version = Saltbox::Actions::VERSION
  spec.authors = ["Sevenview Studios Inc."]
  spec.email = ["dev@sevenview.ca"]

  spec.summary = "One action class per thing a person can do, served to screens, the API, MCP and AI assistants"
  spec.description = "An action layer for Rails apps: actions named from their class, checked at boot, " \
    "authorized through Pundit or ActionPolicy, and served by the same code to a JSON API, MCP and RubyLLM tools. " \
    "Ships an RSpec layer (spec type, callers, matchers, shared examples) and generators. " \
    "Part of the Saltbox gem suite extracted from internal applications."
  spec.homepage = "https://github.com/myunio/saltbox-actions"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*", "*.{md,txt,gemspec}", "LICENSE.txt"].select { |f| File.file?(f) }
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "json_schemer", "~> 2.5"
end
