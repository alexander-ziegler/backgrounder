# frozen_string_literal: true

# Main entry point for the Backgrounder gem
# Provides configuration, job definition DSL, and access to job runner and WAL
# See README for usage examples and DDIA-inspired architecture

require_relative "backgrounder/version"
require_relative "backgrounder/job"
require_relative "backgrounder/runner"
require_relative "backgrounder/dsl"
require_relative "backgrounder/wal/file_storage"
require_relative "backgrounder/wal/entry"

module Backgrounder
  # Error class for gem-specific errors
  class Error < StandardError; end

  # Expose DSL and Runner for user convenience
  DSL = Backgrounder::DSL
  Runner = Backgrounder::Runner
  Job = Backgrounder::Job
  WAL = Backgrounder::WAL

  # Main configuration and entry point for the gem
  # Handles global settings, job registration, and runner lifecycle
  # TODO: Add configuration DSL and registry
end
