# frozen_string_literal: true

# Internal job registry and configuration for Backgrounder DSL.
module Backgrounder
  # DSL provides methods for configuring and defining jobs.
  module DSL
    # @!attribute [rw] job_registry
    #   @return [Hash] The registry of defined jobs
    # @!attribute [rw] config
    #   @return [Struct] The configuration struct
    @job_registry = {}
    @config = Struct.new(:max_threads, :retry_limit, :logger, :storage).new

    class << self
      attr_reader :job_registry, :config

      # Configure Backgrounder DSL.
      # @yieldparam config [Struct] The configuration struct
      # @return [void]
      def configure
        yield config
      end

      # Define a background job.
      # @param name [Symbol, String] The job name
      # @param opts [Hash] Options for the job (e.g., :retry, :exclusive)
      # @yield The job block to execute
      # @return [void]
      def define_job(name, opts = {}, &block)
        raise ArgumentError, "Block required for job definition" unless block_given?

        job_def = {
          name: name.to_sym,
          opts: opts,
          block: block
        }
        job_registry[name.to_sym] = job_def
      end

      # Lookup a job definition by name.
      # @param name [Symbol, String]
      # @return [Hash, nil] The job definition or nil if not found
      def get_job(name)
        job_registry[name.to_sym]
      end

      # List all defined job names.
      # @return [Array<Symbol>] List of job names
      def jobs
        job_registry.keys
      end
    end
  end
end
