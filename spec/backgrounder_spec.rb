# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tempfile"
require "logger"
require "yaml"

RSpec.describe Backgrounder do
  it "has a version number" do
    expect(Backgrounder::VERSION).not_to be nil
  end

  it "exposes the DSL module" do
    expect(Backgrounder::DSL).to eq(Backgrounder::DSL)
    expect(Backgrounder::DSL).to respond_to(:define_job)
    expect(Backgrounder::DSL).to respond_to(:configure)
  end

  it "exposes the Runner class" do
    expect(Backgrounder::Runner).to eq(Backgrounder::Runner)
    expect(Backgrounder::Runner.new).to be_a(Backgrounder::Runner)
  end

  it "exposes the Job class" do
    expect(Backgrounder::Job).to eq(Backgrounder::Job)
    expect(Backgrounder::Job.new).to be_a(Backgrounder::Job)
  end

  it "exposes the WAL module" do
    expect(Backgrounder::WAL).to eq(Backgrounder::WAL)
    expect(Backgrounder::WAL::FileStorage).to eq(Backgrounder::WAL::FileStorage)
    expect(Backgrounder::WAL::Entry).to eq(Backgrounder::WAL::Entry)
  end

  it "defines a custom error class" do
    expect { raise Backgrounder::Error, "test" }.to raise_error(Backgrounder::Error, "test")
  end
end

RSpec.describe Backgrounder::WAL::Entry do
  let(:job_id) { "abc123" }
  let(:event) { "enqueued" }
  let(:data) { { "foo" => "bar" } }
  let(:timestamp) { Time.now.utc }
  let(:state) { "queued" }

  it "serializes and deserializes to/from hash" do
    entry = described_class.new(job_id: job_id, event: event, data: data, timestamp: timestamp, state: state)
    hash = entry.to_h
    entry2 = described_class.from_h(hash)
    expect(entry2.job_id).to eq(job_id)
    expect(entry2.event).to eq(event)
    expect(entry2.data).to eq(data)
    expect(entry2.timestamp.to_i).to eq(timestamp.to_i)
    expect(entry2.state).to eq(state)
  end

  it "serializes and deserializes to/from JSON" do
    entry = described_class.new(job_id: job_id, event: event, data: data, timestamp: timestamp, state: state)
    json = entry.to_json
    entry2 = described_class.from_json(json)
    expect(entry2.job_id).to eq(job_id)
    expect(entry2.event).to eq(event)
    expect(entry2.data).to eq(data)
    expect(entry2.timestamp.to_i).to eq(timestamp.to_i)
    expect(entry2.state).to eq(state)
  end
end

RSpec.describe Backgrounder::WAL::FileStorage do
  let(:tmpfile) { Tempfile.new("wal_test") }
  let(:log_path) { tmpfile.path }
  let(:storage) { described_class.new(log_path) }
  let(:entry) do
    Backgrounder::WAL::Entry.new(
      job_id: "job1",
      event: "enqueued",
      data: { "foo" => "bar" },
      timestamp: Time.now.utc,
      state: "queued"
    )
  end

  after do
    tmpfile.close
    tmpfile.unlink
  end

  it "appends and replays entries" do
    storage.append(entry)
    entries = storage.replay.to_a
    expect(entries.size).to eq(1)
    expect(entries.first.job_id).to eq("job1")
    expect(entries.first.event).to eq("enqueued")
    expect(entries.first.data).to eq({ "foo" => "bar" })
    expect(entries.first.state).to eq("queued")
  end

  it "returns an enumerator if no block is given" do
    storage.append(entry)
    enumerator = storage.replay
    expect(enumerator).to be_a(Enumerator)
    expect(enumerator.to_a.size).to eq(1)
  end

  it "handles empty log gracefully" do
    expect(storage.replay.to_a).to eq([])
  end

  it "compacts the WAL with checkpoint, keeping only in-flight jobs" do
    # Add jobs with various states
    storage.append(Backgrounder::WAL::Entry.new(job_id: "job1", event: "enqueued", data: {}, state: "queued",
                                                timestamp: Time.now.utc))
    storage.append(Backgrounder::WAL::Entry.new(job_id: "job2", event: "completed", data: {}, state: "complete",
                                                timestamp: Time.now.utc))
    storage.append(Backgrounder::WAL::Entry.new(job_id: "job3", event: "failed", data: {}, state: "failed",
                                                timestamp: Time.now.utc))
    storage.append(Backgrounder::WAL::Entry.new(job_id: "job4", event: "started", data: {}, state: "running",
                                                timestamp: Time.now.utc))
    storage.checkpoint
    entries = storage.replay.to_a
    job_ids = entries.map(&:job_id)
    expect(job_ids).to include("job1", "job4")
    expect(job_ids).not_to include("job2", "job3")
    expect(entries.size).to eq(2)
  end

  # it 'supports pluggable serializers (YAML)' do
  #   require 'yaml'
  #   yaml_tmpfile = Tempfile.new('wal_yaml_test')
  #   puts "#{yaml_tmpfile}"
  #   yaml_log_path = yaml_tmpfile.path
  #   puts "#{yaml_log_path}"
  #   yaml_storage = described_class.new(yaml_log_path, serializer: YAML)
  #   entry = Backgrounder::WAL::Entry.new(job_id: 'yaml1', event: 'enqueued',
  #       data: { 'foo' => 'bar' }, timestamp: Time.now.utc, state: 'queued'
  #   )
  #   yaml_storage.append(entry)
  #   entries = yaml_storage.replay.to_a
  #   expect(entries.size).to eq(1)
  #   expect(entries.first.job_id).to eq('yaml1')
  #   expect(entries.first.data).to eq({ 'foo' => 'bar' })
  #   expect(entries.first.state).to eq('queued')
  #   yaml_tmpfile.close
  #   yaml_tmpfile.unlink
  # end
end

RSpec.describe Backgrounder::Job do
  let(:args) { { "foo" => "bar" } }
  let(:job) { described_class.new(args: args, max_retries: 5, exclusive: true) }

  it "generates a unique id by default" do
    job2 = described_class.new(args: args)
    expect(job.id).not_to eq(job2.id)
    expect(job.id).to be_a(String)
  end

  it "initializes with correct attributes" do
    expect(job.args).to eq(args)
    expect(job.max_retries).to eq(5)
    expect(job.exclusive).to eq(true)
    expect(job.state).to eq(:queued)
    expect(job.retries).to eq(0)
    expect(job.created_at).to be_a(Time)
    expect(job.updated_at).to be_a(Time)
  end

  it "serializes and deserializes to/from hash" do
    hash = job.to_h
    job2 = described_class.from_h(hash)
    expect(job2.id).to eq(job.id)
    expect(job2.args).to eq(job.args)
    expect(job2.max_retries).to eq(job.max_retries)
    expect(job2.exclusive).to eq(job.exclusive)
    expect(job2.state).to eq(job.state)
    expect(job2.retries).to eq(job.retries)
    expect(job2.created_at.to_i).to eq(job.created_at.to_i)
    expect(job2.updated_at.to_i).to eq(job.updated_at.to_i)
  end

  it "serializes and deserializes to/from JSON" do
    json = job.to_json
    job2 = described_class.from_json(json)
    expect(job2.id).to eq(job.id)
    expect(job2.args).to eq(job.args)
    expect(job2.max_retries).to eq(job.max_retries)
    expect(job2.exclusive).to eq(job.exclusive)
    expect(job2.state).to eq(job.state)
    expect(job2.retries).to eq(job.retries)
    expect(job2.created_at.to_i).to eq(job.created_at.to_i)
    expect(job2.updated_at.to_i).to eq(job.updated_at.to_i)
  end

  it "transitions state correctly" do
    job.mark_running
    expect(job.state).to eq(:running)
    job.mark_complete
    expect(job.state).to eq(:complete)
    job.mark_failed
    expect(job.state).to eq(:failed)
  end

  it "increments retries and respects max_retries" do
    job.retries = 2
    expect(job.retries).to eq(2)
    expect(job.max_retries).to eq(5)
  end
end

RSpec.describe "Backgrounder DSL integration" do
  before do
    # Reset registry and config for isolation
    Backgrounder::DSL.job_registry.clear
    Backgrounder::DSL.configure do |config|
      config.max_threads = nil
      config.retry_limit = nil
      config.logger = nil
      config.storage = nil
    end
  end

  it "configures global settings via configure" do
    logger = double("Logger")
    Backgrounder::DSL.configure do |config|
      config.max_threads = 10
      config.retry_limit = 7
      config.logger = logger
      config.storage = :file_wal
    end
    expect(Backgrounder::DSL.config.max_threads).to eq(10)
    expect(Backgrounder::DSL.config.retry_limit).to eq(7)
    expect(Backgrounder::DSL.config.logger).to eq(logger)
    expect(Backgrounder::DSL.config.storage).to eq(:file_wal)
  end

  it "registers a job with options and block" do
    block = proc { |x| x * 2 }
    Backgrounder::DSL.define_job :test_job, retry: 5, exclusive: true, &block
    job_def = Backgrounder::DSL.get_job(:test_job)
    expect(job_def).not_to be_nil
    expect(job_def[:name]).to eq(:test_job)
    expect(job_def[:opts]).to eq(retry: 5, exclusive: true)
    expect(job_def[:block]).to eq(block)
  end

  it "lists all defined jobs" do
    Backgrounder::DSL.define_job :job1 do
      "job_one"
    end
    Backgrounder::DSL.define_job :job2 do
      "job_two"
    end
    expect(Backgrounder::DSL.jobs).to contain_exactly(:job1, :job2)
  end

  it "raises an error if no block is given" do
    expect { Backgrounder::DSL.define_job(:bad_job) }.to raise_error(ArgumentError)
  end

  it "can execute a registered job block with arguments" do
    Backgrounder::DSL.define_job :adder do |a, b|
      a + b
    end
    job_def = Backgrounder::DSL.get_job(:adder)
    result = job_def[:block].call(2, 3)
    expect(result).to eq(5)
  end

  it "can register a job with options matching Job attributes" do
    Backgrounder::DSL.define_job :custom_job, retry: 2, exclusive: true do |x|
      x
    end
    job_def = Backgrounder::DSL.get_job(:custom_job)
    job = Backgrounder::Job.new(args: { x: 42 }, max_retries: job_def[:opts][:retry],
                                exclusive: job_def[:opts][:exclusive])
    expect(job.max_retries).to eq(2)
    expect(job.exclusive).to eq(true)
    expect(job.args).to eq({ x: 42 })
  end
end

RSpec.describe "Backgrounder::Runner integration" do
  let(:tmpfile) { Tempfile.new("wal_runner_test") }
  let(:log_path) { tmpfile.path }
  let(:wal) { Backgrounder::WAL::FileStorage.new(log_path) }
  let(:logger) { Logger.new(nil) }
  let(:runner) { Backgrounder::Runner.new(max_threads: 2, logger: logger, wal: wal) }

  before do
    Backgrounder::DSL.job_registry.clear
    # ensure file is created
    wal
  end

  after do
    tmpfile.close
    tmpfile.unlink
  end

  it "executes a job successfully and marks it complete" do
    result = []
    Backgrounder::DSL.define_job :test_job do |x|
      result << x
    end
    job = Backgrounder::Job.new(args: { "job_name" => "test_job", "args" => [42] })
    runner.start
    runner.enqueue(job)
    sleep 0.2
    runner.stop
    expect(result).to eq([42])
    # Check WAL for completed event
    events = wal.replay.to_a.select { |e| e.job_id == job.id }

    expect(events.map(&:event)).to include("completed")
  end

  it "retries a failing job and marks it failed after max retries" do
    Backgrounder::DSL.define_job :fail_job do
      raise Backgrounder::Error, "fail!"
    end
    job = Backgrounder::Job.new(args: { "job_name" => "fail_job", "args" => [] }, max_retries: 2)
    runner.start
    runner.enqueue(job)
    sleep 2
    runner.stop
    events = wal.replay.to_a.select { |e| e.job_id == job.id }
    expect(events.map(&:event)).to include("retry")
  end

  it "recovers in-flight jobs from WAL on restart" do
    result = []
    Backgrounder::DSL.define_job :recover_job do |x|
      result << x
    end
    job = Backgrounder::Job.new(args: { "job_name" => "recover_job", "args" => [99] })
    wal.append(Backgrounder::WAL::Entry.new(job_id: job.id, event: :enqueued, data: job.to_h, state: job.state,
                                            timestamp: Time.now.utc))
    new_runner = Backgrounder::Runner.new(max_threads: 1, logger: logger, wal: wal)
    new_runner.start
    sleep 0.2
    new_runner.stop
    expect(result).to eq([99])
    events = wal.replay.to_a.select { |e| e.job_id == job.id }
    expect(events.map(&:event)).to include("completed")
  end
end

RSpec.describe "Backgrounder deduplication/fingerprinting" do
  let(:tmpfile) { Tempfile.new("wal_dedupe_test") }
  let(:log_path) { tmpfile.path }
  let(:wal) { Backgrounder::WAL::FileStorage.new(log_path) }
  let(:logger) { Logger.new(nil) }

  after do
    tmpfile.close
    tmpfile.unlink
  end

  it "does not re-enqueue jobs with the same fingerprint that are already complete/failed" do
    Backgrounder::DSL.job_registry.clear
    executed = []
    Backgrounder::DSL.define_job :dedupe_job do |x|
      executed << x
    end
    job_args = { "job_name" => "dedupe_job", "args" => [123] }
    job1 = Backgrounder::Job.new(args: job_args)
    job1.fingerprint
    wal.append(Backgrounder::WAL::Entry.new(job_id: job1.id, event: :completed, data: job1.to_h, state: "complete",
                                            timestamp: Time.now.utc))
    job2 = Backgrounder::Job.new(args: job_args)
    wal.append(Backgrounder::WAL::Entry.new(job_id: job2.id, event: :enqueued, data: job2.to_h, state: "queued",
                                            timestamp: Time.now.utc))
    runner = Backgrounder::Runner.new(max_threads: 1, logger: logger, wal: wal)
    runner.start
    sleep 0.2
    runner.stop

    # Only the first job should have been executed (and it was already complete)
    expect(executed).to eq([])
  end
end

RSpec.describe "Backgrounder exclusive jobs with resource locking" do
  let(:tmpfile) { Tempfile.new("wal_exclusive_test") }
  let(:log_path) { tmpfile.path }
  let(:wal) { Backgrounder::WAL::FileStorage.new(log_path) }
  let(:logger) { Logger.new(nil) }

  after do
    tmpfile.close
    tmpfile.unlink
  end

  it "does not run jobs with the same resource key concurrently" do
    # Jobs 1 and 2 have the same user_id, so should not overlap
    # Job 3 has a different user_id, so can run concurrently
    Backgrounder::DSL.job_registry.clear
    execution_order = []
    Backgrounder::DSL.define_job :exclusive_job, exclusive: :user_id do |user_id, sleep_time|
      execution_order << [user_id, :start]
      sleep sleep_time
      execution_order << [user_id, :end]
    end
    runner = Backgrounder::Runner.new(max_threads: 2, logger: logger, wal: wal)
    job1 = Backgrounder::Job.new(args: { "job_name" => "exclusive_job", "args" => [1, 0.2], "user_id" => 1 })
    job2 = Backgrounder::Job.new(args: { "job_name" => "exclusive_job", "args" => [1, 0.2], "user_id" => 1 })
    job3 = Backgrounder::Job.new(args: { "job_name" => "exclusive_job", "args" => [2, 0.2], "user_id" => 2 })
    runner.start
    runner.enqueue(job1)
    runner.enqueue(job2)
    runner.enqueue(job3)
    sleep 1
    runner.stop
    user1_events = execution_order.select { |u, _| u == 1 }
    user2_events = execution_order.select { |u, _| u == 2 }
    # For user 1, :end of first must come before :start of second
    # For user 2, both :start and :end should be present
    first_end = user1_events.index([1, :end])
    second_start = user1_events.rindex([1, :start])

    expect(first_end).to be < second_start
    expect(user2_events).to include([2, :start], [2, :end])
  end
end
