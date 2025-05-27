# frozen_string_literal: true

require "securerandom"
require "json"
require "digest"

module Backgrounder
  # Represents a background job and its metadata.
  # Supports serialization, deduplication, state transitions, and flexible arguments.
  # @!attribute [rw] id
  #   @return [String] The unique job identifier
  # @!attribute [rw] args
  #   @return [Hash] The job arguments
  # @!attribute [rw] state
  #   @return [Symbol] The job state (:queued, :running, :complete, :failed)
  # @!attribute [rw] retries
  #   @return [Integer] The number of retries attempted
  # @!attribute [rw] max_retries
  #   @return [Integer] The maximum number of retries
  # @!attribute [rw] exclusive
  #   @return [Boolean] Whether the job is exclusive
  # @!attribute [rw] created_at
  #   @return [Time] When the job was created
  # @!attribute [rw] updated_at
  #   @return [Time] When the job was last updated
  # @!attribute [rw] fingerprint
  #   @return [String] The job fingerprint for deduplication
  class Job
    attr_accessor :id, :args, :state, :retries, :max_retries, :exclusive, :created_at, :updated_at, :fingerprint

    # States: :queued, :running, :complete, :failed
    STATES = %i[queued running complete failed].freeze

    # Initialize a new Job.
    # @param args [Hash] The job arguments
    # @param max_retries [Integer] Maximum number of retries
    # @param exclusive [Boolean] Whether the job is exclusive
    # @param id [String, nil] The job ID
    # @param state [Symbol, String] The job state
    # @param retries [Integer] Number of retries attempted
    # @param created_at [Time, nil] Creation time
    # @param updated_at [Time, nil] Last update time
    # @param fingerprint [String, nil] Job fingerprint
    def initialize(args: {}, max_retries: 3, exclusive: false, id: nil, state: :queued, retries: 0, created_at: nil,
                   updated_at: nil, fingerprint: nil)
      @id = id || SecureRandom.uuid
      @args = args
      @state = state.to_sym
      @retries = retries
      @max_retries = max_retries
      @exclusive = exclusive
      @created_at = created_at || Time.now.utc
      @updated_at = updated_at || Time.now.utc
      @fingerprint = fingerprint || generate_fingerprint
    end

    # Serialize job to hash (for WAL, etc.)
    # @return [Hash]
    def to_h
      {
        "id" => id,
        "args" => args,
        "state" => state.to_s,
        "retries" => retries,
        "max_retries" => max_retries,
        "exclusive" => exclusive,
        "created_at" => created_at.iso8601,
        "updated_at" => updated_at.iso8601,
        "fingerprint" => fingerprint
      }
    end

    # Deserialize job from hash.
    # @param hash [Hash]
    # @return [Job]
    def self.from_h(hash)
      new(
        id: hash["id"],
        args: hash["args"],
        state: hash["state"],
        retries: hash["retries"] || 0,
        max_retries: hash["max_retries"] || 3,
        exclusive: hash["exclusive"] || false,
        created_at: Time.parse(hash["created_at"]),
        updated_at: Time.parse(hash["updated_at"]),
        fingerprint: hash["fingerprint"]
      )
    end

    # Serialize to JSON.
    # @param args [Array]
    # @return [String]
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Deserialize from JSON.
    # @param json [String]
    # @return [Job]
    def self.from_json(json)
      from_h(JSON.parse(json))
    end

    # Mark the job as running.
    # @return [void]
    def mark_running
      self.state = :running
      self.updated_at = Time.now.utc
      emit_event(:started)
    end

    # Mark the job as complete.
    # @return [void]
    def mark_complete
      self.state = :complete
      self.updated_at = Time.now.utc
      emit_event(:completed)
    end

    # Mark the job as failed.
    # @return [void]
    def mark_failed
      self.state = :failed
      self.updated_at = Time.now.utc
      emit_event(:failed)
    end

    # Emit job lifecycle events for observability (stub).
    # @param event_type [Symbol]
    # @return [void]
    def emit_event(event_type)
      # TODO: Integrate with logger/metrics/event bus
      # Example: logger.info("Job \\#{id} event: \\#{event_type}")
    end

    # Generate fingerprint for deduplication (SHA256 of job name + args).
    # @return [String]
    def generate_fingerprint
      job_name = args["job_name"] || args[:job_name] || ""
      job_args = args["args"] || args[:args] || args
      Digest::SHA256.hexdigest([job_name, job_args].to_json)
    end
  end
end
