# frozen_string_literal: true

require_relative "lib/miniapm/version"

Gem::Specification.new do |spec|
  spec.name = "miniapm"
  spec.version = MiniAPM::VERSION
  spec.authors = ["Chris Hasinski"]
  spec.email = ["krzysztof.hasinski@gmail.com"]

  spec.summary = "Lightweight APM client for MiniAPM server"
  spec.description = "Ruby gem for Rails APM integration with MiniAPM. Exports traces in OTLP format, captures errors, and provides comprehensive instrumentation for Rails, ActiveRecord, Sidekiq, HTTP clients, Redis, and search engines."
  spec.homepage = "https://miniapm.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/miniapm/miniapm-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/miniapm/miniapm-ruby/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://miniapm.com/docs"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies - uses only Ruby stdlib

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "vcr", "~> 6.2"
  spec.add_development_dependency "timecop", "~> 0.9"
  spec.add_development_dependency "rack", "~> 3.0"
  spec.add_development_dependency "rack-test", "~> 2.1"
end
