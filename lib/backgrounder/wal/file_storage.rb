# frozen_string_literal: true

require 'json'
require 'fileutils'

module Backgrounder
  module WAL
    # Handles append-only log file for job durability and recovery
    # DDIA: Fault tolerance, recovery, checkpointing, pluggable serialization
    class FileStorage
      DEFAULT_LOG_PATH = 'log/jobs.wal'.freeze
      @default_serializer = JSON

      class << self
        attr_accessor :default_serializer
      end

      attr_reader :log_path, :serializer

      def initialize(log_path = DEFAULT_LOG_PATH, serializer: nil)
        @log_path = log_path
        @serializer = serializer || self.class.default_serializer
        FileUtils.mkdir_p(File.dirname(log_path))
      end

      # Append a WAL::Entry to the log
      def append(entry)
        File.open(log_path, 'a') do |f|
          f.puts serializer.dump(entry.to_h)
        end
      end

      # Replay the log, yielding WAL::Entry objects
      def replay
        return enum_for(:replay) unless block_given?
        return unless File.exist?(log_path)
        File.foreach(log_path) do |line|
          hash = serializer.load(line)
          next if hash.nil? || hash == false
          entry = Entry.from_h(hash)
          next unless entry
          yield entry
        end
      end

      # Checkpoint: compact the WAL by keeping only in-flight jobs
      def checkpoint
        return unless File.exist?(log_path)
        in_flight = {}
        replay.each do |entry|
          in_flight[entry.job_id] = entry
        end
        # Only keep jobs not complete/failed
        compacted = in_flight.values.select { |e| !%w[complete failed].include?(e.state.to_s) }
        tmp_path = log_path + ".tmp"
        File.open(tmp_path, 'w') do |f|
          compacted.each { |entry| f.puts serializer.dump(entry.to_h) }
        end
        FileUtils.mv(tmp_path, log_path)
      end

      # Optional: allow pluggable serializers (e.g., YAML, MessagePack)
      # def set_serializer(serializer)
      #   @serializer = serializer
      # end
    end
  end
end
