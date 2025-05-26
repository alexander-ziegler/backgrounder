# frozen_string_literal: true

require 'securerandom'
require 'json'
require 'digest'

module Backgrounder
  # Represents a background job and its metadata
  # DDIA: Idempotence, durability, flexible data model, observability, concurrency/isolation
  class Job
    attr_accessor :id, :args, :state, :retries, :max_retries, :exclusive, :created_at, :updated_at, :fingerprint

    # States: :queued, :running, :complete, :failed
    STATES = %i[queued running complete failed].freeze

    def initialize(args: {}, max_retries: 3, exclusive: false, id: nil, state: :queued, retries: 0, created_at: nil, updated_at: nil, fingerprint: nil)
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
    def to_h
      {
        'id' => id,
        'args' => args,
        'state' => state.to_s,
        'retries' => retries,
        'max_retries' => max_retries,
        'exclusive' => exclusive,
        'created_at' => created_at.iso8601,
        'updated_at' => updated_at.iso8601,
        'fingerprint' => fingerprint
      }
    end

    # Deserialize job from hash
    def self.from_h(hash)
      new(
        id: hash['id'],
        args: hash['args'],
        state: hash['state'],
        retries: hash['retries'] || 0,
        max_retries: hash['max_retries'] || 3,
        exclusive: hash['exclusive'] || false,
        created_at: Time.parse(hash['created_at']),
        updated_at: Time.parse(hash['updated_at']),
        fingerprint: hash['fingerprint']
      )
    end

    # Serialize to JSON
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Deserialize from JSON
    def self.from_json(json)
      from_h(JSON.parse(json))
    end

    # State transitions
    def mark_running
      self.state = :running
      self.updated_at = Time.now.utc
      emit_event(:started)
    end

    def mark_complete
      self.state = :complete
      self.updated_at = Time.now.utc
      emit_event(:completed)
    end

    def mark_failed
      self.state = :failed
      self.updated_at = Time.now.utc
      emit_event(:failed)
    end

    # (Stub) Emit job lifecycle events for observability
    def emit_event(event_type)
      # TODO: Integrate with logger/metrics/event bus
      # Example: logger.info("Job \\#{id} event: \\#{event_type}")
    end

    # Generate fingerprint for deduplication (SHA256 of job name + args)
    def generate_fingerprint
      job_name = args['job_name'] || args[:job_name] || ''
      job_args = args['args'] || args[:args] || args
      Digest::SHA256.hexdigest([job_name, job_args].to_json)
    end
  end
end
