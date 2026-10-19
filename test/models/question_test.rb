require "test_helper"

class QuestionTest < ActiveSupport::TestCase
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

  test "rejects an unknown status" do
    question = Question.new(text: "Why?", status: "skipped")
    assert_not question.valid?
    assert_includes question.errors[:status], "is not included in the list"
  end
end
