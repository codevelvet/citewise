# Allows one running job per document across every job class that includes it,
# whatever their queues. Other jobs for the document wait until it finishes.
module DocumentSerialized
  extend ActiveSupport::Concern

  # Solid Queue takes this lock when the job is dispatched, not when it starts, so the
  # duration must cover time waiting in a backed-up queue plus the run itself. It expires
  # even if the job is still waiting or running, so set it well above both.
  # A crashed worker doesn't hold it this long: dead-process pruning fails the job, and
  # that releases the lock. The expiry is only a backstop.
  LOCK_DURATION = 24.hours

  included do
    limits_concurrency to: 1, key: ->(document, **) { document }, group: "document", duration: LOCK_DURATION
  end
end
