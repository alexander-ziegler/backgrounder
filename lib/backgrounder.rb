# frozen_string_literal: true

require_relative "backgrounder/version"
require_relative "backgrounder/job"
require_relative "backgrounder/runner"
require_relative "backgrounder/dsl"
require_relative "backgrounder/wal/file_storage"
require_relative "backgrounder/wal/entry"

# Main module for the Backgrounder gem.
# Provides configuration, job definition DSL, job runner, and WAL access.
# Use this module to interact with Backgrounder features in your application.
module Backgrounder
  class Error < StandardError; end
end
