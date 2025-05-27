# frozen_string_literal: true

require "json"
require "time"

module Backgrounder
  module WAL
    # Represents a single entry in the Write-Ahead Log (WAL) for job durability and recovery.
    # @!attribute [rw] job_id
    #   @return [String] The unique job identifier
    # @!attribute [rw] event
    #   @return [String, Symbol] The event type (e.g., :enqueued, :started, :completed, :failed)
    # @!attribute [rw] data
    #   @return [Hash] The job data payload
    # @!attribute [rw] timestamp
    #   @return [Time] The time the event was logged
    # @!attribute [rw] state
    #   @return [String, Symbol, nil] The job state
    class Entry
      attr_accessor :job_id, :event, :data, :timestamp, :state

      # Events: :enqueued, :started, :completed, :failed
      # @param job_id [String]
      # @param event [String, Symbol]
      # @param data [Hash]
      # @param timestamp [Time]
      # @param state [String, Symbol, nil]
      def initialize(job_id:, event:, data: {}, timestamp: Time.now.utc, state: nil)
        @job_id = job_id
        @event = event
        @data = data
        @timestamp = timestamp
        @state = state
      end

      # Convert the entry to a hash for serialization.
      # @return [Hash]
      def to_h
        {
          "job_id" => job_id,
          "event" => event,
          "data" => data,
          "timestamp" => timestamp.iso8601,
          "state" => state
        }
      end

      # Create an Entry from a hash.
      # @param hash [Hash]
      # @return [Entry, nil]
      def self.from_h(hash)
        return nil unless hash && hash["job_id"] && hash["event"] && hash["timestamp"]

        new(
          job_id: hash["job_id"],
          event: hash["event"],
          data: hash["data"],
          timestamp: Time.parse(hash["timestamp"]),
          state: hash["state"]
        )
      end

      # Convert the entry to JSON.
      # @param args [Array]
      # @return [String]
      def to_json(*args)
        to_h.to_json(*args)
      end

      # Create an Entry from a JSON string.
      # @param json [String]
      # @return [Entry, nil]
      def self.from_json(json)
        from_h(JSON.parse(json))
      end
    end
  end
end
