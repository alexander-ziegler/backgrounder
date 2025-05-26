# frozen_string_literal: true

require 'json'
require 'time'

module Backgrounder
  module WAL
    # Represents a single entry in the WAL
    # DDIA: Flexible schema, idempotence, event sourcing
    class Entry
      attr_accessor :job_id, :event, :data, :timestamp, :state

      # Events: :enqueued, :started, :completed, :failed
      def initialize(job_id:, event:, data: {}, timestamp: Time.now.utc, state: nil)
        @job_id = job_id
        @event = event
        @data = data
        @timestamp = timestamp
        @state = state
      end

      def to_h
        {
          'job_id' => job_id,
          'event' => event,
          'data' => data,
          'timestamp' => timestamp.iso8601,
          'state' => state
        }
      end

      def self.from_h(hash)
        return nil unless hash && hash['job_id'] && hash['event'] && hash['timestamp']
        new(
          job_id: hash['job_id'],
          event: hash['event'],
          data: hash['data'],
          timestamp: Time.parse(hash['timestamp']),
          state: hash['state']
        )
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      def self.from_json(json)
        from_h(JSON.parse(json))
      end
    end
  end
end
