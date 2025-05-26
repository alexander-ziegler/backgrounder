# Backgrounder Playground

Try out Backgrounder in IRB or a Ruby script! Copy and paste the following code snippets to experiment with job definition, enqueuing, and execution.

---

## 1. Setup (in IRB or a Ruby script)

```ruby
require 'logger'
require_relative './lib/backgrounder'
```

---

## 2. Configure Backgrounder

```ruby
Backgrounder::DSL.configure do |config|
  config.max_threads = 2
  config.retry_limit = 2
  config.logger = Logger.new($stdout)
end
```

---

## 3. Define a Job

```ruby
Backgrounder::DSL.define_job :hello_job do |name|
  puts "Hello, #{name}!"
end
```

---

## 4. Enqueue a Job

```ruby
runner = Backgrounder::Runner.new(max_threads: 2)
job = Backgrounder::Job.new(args: { 'job_name' => 'hello_job', 'args' => ['IRB user'] })
runner.enqueue(job)
```

---

## 5. Start the Runner

```ruby
runner.start
sleep 0.5 # Let the job run
runner.stop
```

---

## 6. Try Exclusive Jobs

```ruby
Backgrounder::DSL.define_job :exclusive_job, exclusive: :user_id do |user_id|
  puts "Running exclusive job for user \\#{user_id}"
  sleep 0.2
end

runner = Backgrounder::Runner.new(max_threads: 2)
job1 = Backgrounder::Job.new(args: { 'job_name' => 'exclusive_job', 'args' => [1], 'user_id' => 1 })
job2 = Backgrounder::Job.new(args: { 'job_name' => 'exclusive_job', 'args' => [1], 'user_id' => 1 })
job3 = Backgrounder::Job.new(args: { 'job_name' => 'exclusive_job', 'args' => [2], 'user_id' => 2 })
runner.enqueue(job1)
runner.enqueue(job2)
runner.enqueue(job3)
runner.start
sleep 1
runner.stop
```

---

## 7. WAL Checkpointing

```ruby
runner.wal.checkpoint
```

---

## 8. Using YAML as the WAL Serializer

```ruby
require 'yaml'
yaml_runner = Backgrounder::Runner.new(wal: Backgrounder::WAL::FileStorage.new('log/jobs.yaml', serializer: YAML))
```

---

Happy experimenting! 