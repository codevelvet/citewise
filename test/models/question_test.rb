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

  test "rejects an unknown status" do
    question = Question.new(text: "Why?", status: "skipped")
    assert_not question.valid?
    assert_includes question.errors[:status], "is not included in the list"
  end
end
