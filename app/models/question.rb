class Question < ApplicationRecord
  # Answering::AskService gives up on its own after about 32 minutes (a 60s embedding
  # timeout, then three 600s answering attempts), plus any wait a retry-after header asks
  # for between attempts. The cutoff allows about an hour for that, so a question pending
  # longer was abandoned: the process died mid-request, or it predates AskService marking
  # every error failed.
  ABANDONED_AFTER = 1.hour
  ABANDONED_ERROR = "Still pending after #{ABANDONED_AFTER.inspect}: the process answering it likely died".freeze

  enum :status, { pending: "pending", answered: "answered", failed: "failed" }, validate: true

  # Caps embedding and answering cost per question. Real questions are far shorter.
  MAX_TEXT_LENGTH = 4_000

  validates :text, presence: true, length: { maximum: MAX_TEXT_LENGTH }

  # Stop reasons for a finished answer. Anything else, including reasons a
  # future SDK adds, is flagged: a needless warning is cheaper than a cut-off
  # answer shown as whole. Add "stop_sequence" here if stop sequences are set.
  COMPLETE_STOP_REASONS = %w[end_turn].freeze

  # The answerer stopped before finishing, so the saved answer may be partial.
  # nil means no stop reason was recorded: the answerer wasn't called (no
  # sources), or the answer predates the stop_reason column. Both count as complete.
  def incomplete? = stop_reason.present? && !COMPLETE_STOP_REASONS.include?(stop_reason)

  # Marks abandoned questions failed and returns how many. Runs from config/recurring.yml
  # and bin/rails citewise:fail_abandoned_questions.
  def self.fail_abandoned
    pending.where(created_at: ...ABANDONED_AFTER.ago).update_all(status: :failed, error: ABANDONED_ERROR, updated_at: Time.current)
  end

  # Failed by fail_abandoned rather than by an error while answering.
  def abandoned? = failed? && error == ABANDONED_ERROR

  # The answer split into text and citation markers, and its sources, for the page.
  def cited_answer = @cited_answer ||= CitedAnswer.new(answer, citations)
end
