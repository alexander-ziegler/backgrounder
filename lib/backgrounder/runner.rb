# frozen_string_literal: true

require "set"

module Backgrounder
  # Executes background jobs, manages worker threads, concurrency, and recovery.
  # Handles job queueing, WAL integration, retries, and exclusive resource locking.
  # @!attribute [rw] max_threads
  #   @return [Integer] Maximum number of worker threads
  # @!attribute [rw] logger
  #   @return [Logger] Logger instance
  # @!attribute [rw] wal
  #   @return [Backgrounder::WAL::FileStorage] WAL storage
  # @!attribute [rw] job_queue
  #   @return [Queue] Thread-safe job queue
  # @!attribute [rw] threads
  #   @return [Array<Thread>] Worker threads
  # @!attribute [rw] running
  #   @return [Boolean] Whether the runner is running
  class Runner
    attr_reader :max_threads, :logger, :wal, :job_queue, :threads, :running

    # Initialize a new Runner.
    # @param max_threads [Integer] Number of worker threads
    # @param logger [Logger, nil] Logger instance
    # @param wal [Backgrounder::WAL::FileStorage, nil] WAL storage
    def initialize(max_threads: 5, logger: nil, wal: nil)
      @max_threads = max_threads
      @logger = logger || Logger.new($stdout)
      @wal = wal || WAL::FileStorage.new
      @job_queue = Queue.new
      @threads = []
      @running = false
      @mutexes = Hash.new { |h, k| h[k] = Mutex.new }
    end

    # Start the runner: recover jobs, start worker threads.
    # @return [void]
    def start
      @running = true
      recover_from_wal
      @threads.clear
      max_threads.times do
        threads << Thread.new { worker_loop }
      end
    end

    # Stop the runner and wait for threads to finish.
    # @return [void]
    def stop
      @running = false
      max_threads.times { job_queue << :shutdown }
      threads.each(&:join)
    end

    # Enqueue a job for execution and log to WAL.
    # @param job [Backgrounder::Job]
    # @return [void]
    def enqueue(job)
      wal.append(WAL::Entry.new(job_id: job.id, event: :enqueued, data: job.to_h, state: job.state,
                                timestamp: Time.now.utc))
      job_queue << job
    end

    # Worker thread loop: execute jobs from the queue.
    # @return [void]
    def worker_loop
      while @running
        begin
          job = job_queue.pop
          break if job == :shutdown

          execute_job(job)
        rescue Backgrounder::Error => e
          logger.error("Worker thread error: #{e}\n#{e.backtrace.join("\n")}")
        end
      end
    end

    # Execute a single job, handle retries and state transitions.
    # @param job [Backgrounder::Job]
    # @return [void]
    def execute_job(job)
      job_def = DSL.get_job(job.args["job_name"]&.to_sym)
      exclusive = job_def && job_def[:opts][:exclusive]
      lock_key = nil
      if exclusive
        lock_key =
          case exclusive
          when TrueClass
            job.args["job_name"]
          when Symbol, String
            job.args[exclusive.to_s] || job.args[exclusive.to_sym]
          when Proc
            exclusive.call(job.args)
          else
            job.args["job_name"]
          end
      end
      if lock_key
        @mutexes[lock_key].synchronize { execute_job_inner(job, job_def) }
      else
        execute_job_inner(job, job_def)
      end
    end

    # Internal: actually execute the job block, handle state and retries.
    # @param job [Backgrounder::Job]
    # @param job_def [Hash, nil]
    # @return [void]
    def execute_job_inner(job, job_def)
      job.mark_running
      wal.append(WAL::Entry.new(job_id: job.id, event: :started, data: job.to_h, state: job.state,
                                timestamp: Time.now.utc))
      if job_def.nil?
        logger.error("No job definition for #{job.args["job_name"]}")
        job.mark_failed
        wal.append(WAL::Entry.new(job_id: job.id, event: :failed, data: job.to_h, state: job.state,
                                  timestamp: Time.now.utc))
        return
      end
      # Execute the job block with args
      job_def[:block].call(*job.args["args"])
      job.mark_complete
      wal.append(WAL::Entry.new(job_id: job.id, event: :completed, data: job.to_h, state: job.state,
                                timestamp: Time.now.utc))
    rescue Backgrounder::Error => e
      logger.error("Job #{job.id} failed: #{e}")
      job.retries += 1
      if job.retries <= job.max_retries
        wal.append(WAL::Entry.new(job_id: job.id, event: :retry, data: job.to_h, state: job.state,
                                  timestamp: Time.now.utc))
        # Exponential backoff (simple sleep for now)
        sleep(2**job.retries)
        job_queue << job
      else
        job.mark_failed
        wal.append(WAL::Entry.new(job_id: job.id, event: :failed, data: job.to_h, state: job.state,
                                  timestamp: Time.now.utc))
      end
    end

    # Recover jobs from WAL (replay and enqueue in-flight jobs).
    # @return [void]
    def recover_from_wal
      in_flight = {}
      completed_fingerprints = Set.new
      wal.replay.each do |entry|
        # Only keep the latest state for each job
        in_flight[entry.job_id] = entry
        # Track fingerprints of completed/failed jobs
        if %w[complete failed].include?(entry.state.to_s) && entry.data["fingerprint"]
          completed_fingerprints << entry.data["fingerprint"]
        end
      end
      in_flight.each_value do |entry|
        # Only re-enqueue jobs not complete/failed and not already completed by fingerprint
        next if %w[complete failed].include?(entry.state.to_s)

        fingerprint = entry.data["fingerprint"]
        next if fingerprint && completed_fingerprints.include?(fingerprint)

        job_hash = entry.data.merge("job_name" => entry.data["job_name"])
        job = Job.from_h(job_hash)
        job_queue << job
      end
    end
  end
end
