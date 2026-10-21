require "test_helper"
require "turbo/broadcastable/test_helper"

class QuestionTest < ActiveSupport::TestCase
  # turbo-rails includes this only once Action Cable has loaded, which depends on test order.
  include Turbo::Broadcastable::TestHelper

  test "starts pending with empty retrieval and citations" do
    question = Question.create!(text: "How much paid leave do I get?")
    assert question.pending?
    assert_equal [ [], [] ], [ question.retrieval, question.citations ]
  end

  test "requires text" do
    question = Question.new
    assert_not question.valid?
    assert_includes question.errors[:text], "can't be blank"
  end

  test "incomplete for every stop reason except end_turn, including ones the SDK adds later" do
    %w[max_tokens refusal model_context_window_exceeded tool_use pause_turn stop_sequence missing something_new].each do |reason|
      assert Question.new(stop_reason: reason).incomplete?, reason
    end
    assert_not Question.new(stop_reason: "end_turn").incomplete?
  end

  test "not incomplete without a stop reason: no sources, or answered before the column existed" do
    assert_not Question.new(stop_reason: nil).incomplete?
  end

  test "limits text to MAX_TEXT_LENGTH characters" do
    assert Question.new(text: "a" * Question::MAX_TEXT_LENGTH).valid?

    question = Question.new(text: "a" * (Question::MAX_TEXT_LENGTH + 1))
    assert_not question.valid?
    assert_includes question.errors[:text], "is too long (maximum is 4000 characters)"
  end

  test "fail_abandoned fails questions pending for over an hour and leaves the rest" do
    abandoned = Question.create!(text: "Abandoned?", created_at: 61.minutes.ago)
    running = Question.create!(text: "Still running?", created_at: 59.minutes.ago)
    answered = Question.create!(text: "Answered?", status: :answered, created_at: 2.hours.ago)

    assert_equal 1, Question.fail_abandoned
    assert abandoned.reload.failed?
    assert_equal "Still pending after 1 hour: the process answering it likely died", abandoned.error
    assert running.reload.pending?
    assert answered.reload.answered?
  end

  test "abandoned only when the sweep failed it" do
    swept = Question.create!(text: "Abandoned?", created_at: 2.hours.ago)
    Question.fail_abandoned

    assert swept.reload.abandoned?
    assert_not Question.new(status: :failed, error: "Answering provider 529: Overloaded").abandoned?
    assert_not Question.new(status: :pending).abandoned?
  end

  test "broadcasts a replacement of its answer section, and a status message, when its status changes" do
    question = Question.create!(text: "How much leave?")

    broadcasts = capture_turbo_stream_broadcasts(question) { question.update!(status: :failed, error: "boom") }

    replace, update = broadcasts
    assert_equal [ "replace", "answer_question_#{question.id}" ], [ replace["action"], replace["target"] ]
    assert_includes replace.at("template").inner_html, %(data-question-status="failed")
    assert_equal [ "update", "status_question_#{question.id}", "Citewise couldn't answer this question." ],
                 [ update["action"], update["target"], update.at("template").text ]
  end

  test "doesn't broadcast when other attributes change, or when the sweep fails it" do
    question = Question.create!(text: "How much leave?", created_at: 2.hours.ago)

    assert_no_turbo_stream_broadcasts(question) do
      question.update!(retrieval: [ { chunk_id: 1 } ], retrieval_ms: 12)
      Question.fail_abandoned
    end
  end

  test "rejects an unknown status" do
    question = Question.new(text: "Why?", status: "skipped")
    assert_not question.valid?
    assert_includes question.errors[:status], "is not included in the list"
  end
end
