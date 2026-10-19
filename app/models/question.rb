class Question < ApplicationRecord
  # Answering::AskService finishes within about 32 minutes at worst (Voyage's 60s timeout
  # plus three 600s Claude attempts), so a question pending longer was abandoned: the
  # process died mid-request, or it predates AskService marking every error failed.
  ABANDONED_AFTER = 1.hour

  enum :status, { pending: "pending", answered: "answered", failed: "failed" }, validate: true

  validates :text, presence: true

  # Marks abandoned questions failed and returns how many. Runs from config/recurring.yml
  # and bin/rails citewise:fail_abandoned_questions.
  def self.fail_abandoned
    pending.where(created_at: ...ABANDONED_AFTER.ago).update_all(
      status: :failed, error: "Still pending after #{ABANDONED_AFTER.inspect}: the process answering it likely died", updated_at: Time.current)
  end
end
