# frozen_string_literal: true

module Backgrounder
  module DSL
    # Internal job registry
    @job_registry = {}
    @config = Struct.new(:max_threads, :retry_limit, :logger, :storage).new

    class << self
      attr_reader :job_registry, :config

      # DSL for configuring Backgrounder
      def configure
        yield config
      end

      # DSL for defining a job
      # Example: define_job :my_job, retry: 3, exclusive: true do |arg1, arg2| ... end
      def define_job(name, opts = {}, &block)
        raise ArgumentError, 'Block required for job definition' unless block_given?
        job_def = {
          name: name.to_sym,
          opts: opts,
          block: block
        }
        job_registry[name.to_sym] = job_def
      end

      # Lookup a job definition by name
      def get_job(name)
        job_registry[name.to_sym]
      end

      # (Stub) List all defined jobs
      def jobs
        job_registry.keys
      end
    end
  end
end
