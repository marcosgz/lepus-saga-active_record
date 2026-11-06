# frozen_string_literal: true

require_relative "lib/lepus/saga/active_record/version"

Gem::Specification.new do |spec|
  spec.name = "lepus-saga-active_record"
  spec.version = Lepus::Saga::ActiveRecord::VERSION
  spec.authors = ["Marcos G. Zimmermann"]
  spec.email = ["mgzmaster@gmail.com"]

  spec.summary = "ActiveRecord store for Lepus::Saga"
  spec.description = "Keeps lepus-saga executions and step attempts in ActiveRecord tables (PostgreSQL, MySQL/MariaDB, SQLite), with a Rails generator for the migration"
  spec.homepage = "https://github.com/marcosgz/lepus-saga-active_record"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/marcosgz/lepus-saga-active_record"
  spec.metadata["changelog_uri"] = "https://github.com/marcosgz/lepus-saga-active_record/blob/master/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|ci|test|spec|features)/|\.(?:git|github|rspec|rubocop)|docker-compose)})
    end
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "lepus-saga", "~> 0.3.1"
  spec.add_dependency "activerecord", ">= 8.0"
  spec.add_development_dependency "activejob"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "railties"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-performance"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "standard"
end
