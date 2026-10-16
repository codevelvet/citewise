require "test_helper"

class QueueConfigTest < ActiveSupport::TestCase
  test "a Solid Queue worker serves every job's queue" do
    Rails.application.eager_load!
    config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/queue.yml"))

    %w[development test production].each do |env|
      served = config.fetch(env).fetch("workers").flat_map { Array(it["queues"]) }
      ApplicationJob.descendants.each do |job|
        assert_includes served, job.queue_name, "#{job} uses a queue no #{env} worker in config/queue.yml serves"
      end
    end
  end
end
