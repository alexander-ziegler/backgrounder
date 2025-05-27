# Backgrounder

A lightweight, simple background job system for Ruby.

## Overview

**Backgrounder** provides a DSL for defining background jobs, executed via threads (or fibers, in the future) without relying on external queue processors like Sidekiq or Redis. It is ideal for:

- Small apps that don't want Redis or external dependencies
- Developers who want more visibility and control over job processing
- Educational and research projects exploring job durability, recovery, and concurrency

## Key Features

- **Write-Ahead Log (WAL):** Durable, append-only log for job recovery and fault tolerance
- **At-Least-Once Delivery:** Jobs are retried with exponential backoff until successful or failed
- **Job Isolation:** Jobs run in isolated threads, with support for exclusive resource locking
- **Flexible Data Model:** JSON-based logs, pluggable serializers (YAML, etc.)
- **Observability:** Job lifecycle events, logger integration, and stubs for metrics/event hooks
- **No External Dependencies:** No Redis or database required

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'backgrounder', path: 'path/to/your/local/backgrounder'
```

And then execute:

    $ bundle install

## Usage

### Configuration

```ruby
Backgrounder::DSL.configure do |config|
  config.max_threads = 5
  config.retry_limit = 3
  config.logger = Logger.new($stdout)
  config.storage = :file_wal # (future: :redis, :s3, etc.)
end
```

### Defining Jobs

```ruby
Backgrounder::DSL.define_job :send_welcome_email, retry: 5, exclusive: :user_id do |user_id|
  user = User.find(user_id)
  Mailer.send_email(user.email)
end

Backgrounder::DSL.define_job :data_import, exclusive: true do |file_path|
  # Only one import job runs at a time
  import_data(file_path)
end
```

### Enqueuing and Running Jobs

```ruby
runner = Backgrounder::Runner.new(max_threads: 3)

# Enqueue a job
job = Backgrounder::Job.new(args: { 'job_name' => 'send_welcome_email', 'args' => [42], 'user_id' => 42 })
runner.enqueue(job)

# Start the runner (in your app, or in a background thread)
runner.start

# Stop the runner gracefully
runner.stop
```

### WAL Checkpointing

```ruby
runner.wal.checkpoint # Compacts the WAL, keeping only in-flight jobs
```

### Pluggable Serializers

```ruby
require 'yaml'
yaml_runner = Backgrounder::Runner.new(wal: Backgrounder::WAL::FileStorage.new('log/jobs.yaml', serializer: YAML))
```

### Exclusive Jobs by Resource

```ruby
Backgrounder::DSL.define_job :user_report, exclusive: :user_id do |user_id|
  # Only one report per user runs at a time
end
```

## Development

- Clone the repo and run `bundle install`.
- Run tests with `bundle exec rspec`.
- Use the included playground (see `PLAYGROUND.md`) for interactive experimentation.

## Contributing

Bug reports and pull requests are welcome! Please:
- Fork the repo and create a feature branch
- Add tests for new features
- Open a pull request with a clear description

## License

This project is licensed under the MIT License. See `LICENSE.txt` for details.
