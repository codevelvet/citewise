require "test_helper"

class QuestionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include StubHelper

  ANSWER = "Full-time employees accrue 20 days of paid leave per year. Ask HR about the rest."

  setup do
    Rails.configuration.x.ask_page[:rate_limit_store].clear
  end

  test "the root shows the empty ask page, without the header ask box" do
    get root_path

    assert_response :success
    assert_select "h1", "Ask the handbook"
    assert_select "textarea[name='question[text]'][maxlength='4000']"
    assert_select "#ask-top", count: 0
    assert_select "a[href=?]", new_question_path(text: "Can a team member be on loan to another team?")
  end

  test "new pre-fills the box from text without asking anything" do
    assert_no_difference -> { Question.count } do
      get new_question_path(text: "How much leave?")
    end

    assert_select "textarea[name='question[text]']", "How much leave?"
    assert_no_enqueued_jobs
  end

  test "create saves a pending question, enqueues AskJob, and redirects to it" do
    assert_difference -> { Question.count }, 1 do
      assert_enqueued_with(job: AskJob) { post questions_path, params: { question: { text: "How much leave?" } } }
    end

    question = Question.last
    assert question.pending?
    assert_equal "How much leave?", question.text
    assert_redirected_to question_path(question)
    assert_equal "default", enqueued_jobs.sole["queue_name"]
  end

  test "create re-renders the form with 422 for blank or overlong text" do
    [ "", "   ", "a" * (Question::MAX_TEXT_LENGTH + 1) ].each do |text|
      assert_no_difference -> { Question.count } do
        post questions_path, params: { question: { text: text } }
      end
      assert_response :unprocessable_content
      assert_select "textarea[name='question[text]'][aria-invalid=true]"
      assert_select "[role=alert]", /Your question (can't be blank|is too long)/
    end
    assert_no_enqueued_jobs
  end

  test "create allows #{QuestionsController::LIMITS[:per_minute]} questions a minute per IP, then returns 429" do
    3.times { ask(ip: "203.0.113.1") }
    assert_no_difference -> { Question.count } do
      ask(ip: "203.0.113.1")
    end
    assert_response :too_many_requests
    assert_select "h1", /asking faster/

    ask(ip: "203.0.113.2")
    assert_response :redirect, "another IP has its own limit"

    travel 61.seconds do
      ask(ip: "203.0.113.1")
      assert_response :redirect
    end
  end

  test "create allows #{QuestionsController::LIMITS[:per_hour]} questions an hour per IP" do
    10.times do |minute|
      travel_to (minute * 2).minutes.from_now do
        3.times { ask(ip: "203.0.113.1") }
      end
    end
    assert_equal 30, Question.count

    travel_to 25.minutes.from_now do
      ask(ip: "203.0.113.1")
      assert_response :too_many_requests
    end
  end

  test "create refuses everyone with 429 once #{QuestionsController::LIMITS[:per_day]} questions were asked in 24 hours" do
    Question.insert_all(Array.new(99) { { text: "Earlier?", created_at: 1.hour.ago, updated_at: 1.hour.ago } })
    Question.create!(text: "Yesterday?", created_at: 25.hours.ago)

    ask(ip: "203.0.113.1")
    assert_response :redirect

    assert_no_difference -> { Question.count } do
      ask(ip: "203.0.113.2")
    end
    assert_response :too_many_requests
    assert_select "h1", /all the questions it can for today/
  end

  test "show renders a pending question with a live region, placeholders, and its stream" do
    question = asked

    get question_path(question)

    assert_response :success
    assert_select "h1", "How much leave?"
    assert_select "#ask-top"
    assert_select "##{dom_id(question, :status)}[role=status]"
    assert_select "##{dom_id(question, :answer)}[data-question-status=pending] article[aria-busy=true]"
    assert_select "[data-controller=answer-refresh][data-answer-refresh-url-value=?] turbo-cable-stream-source", answer_question_path(question, format: :turbo_stream)
  end

  test "show renders the answer with markers, wrapped spans, and one card per source" do
    question = answered_question

    get question_path(question)

    assert_select "p", /Answered in 1.5 seconds · 1 source/
    assert_select "article[aria-label=Answer] span[data-citation-ids='0'][data-source-numbers='1']", "Full-time employees accrue 20 days of paid leave per year."
    assert_select "article[aria-label=Answer] a[href='#source-1'][aria-label='Source 1']", "1"
    assert_select "article[aria-label=Answer] p", /Ask HR about the rest\./
    assert_select "p", /Sentences without a number connect the cited points/
    assert_select "section#source-1" do
      assert_select "h3", /Employee Handbook/
      assert_select "p", "Employee Handbook > Benefits > Paid leave"
      assert_select "blockquote[data-citation-ids='0'] p", chunks(:leave).content
    end
    assert_select "[role=note]", count: 0
  end

  test "show escapes the answer and passages" do
    question = answered_question(answer: "<script>alert(1)</script> Ask HR.", cited_text: "<img src=x onerror=alert(1)>")

    get question_path(question)

    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_not_includes response.body, "<img src=x"
    assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "show warns above an incomplete answer, in plain language, with the raw reason" do
    { "max_tokens" => "This answer was cut off", "refusal" => "This answer stopped early",
      "model_context_window_exceeded" => "This answer was cut off", "missing" => "This answer may be incomplete",
      "pause_turn" => "This answer stopped early" }.each do |reason, title|
      question ||= answered_question
      question.update!(stop_reason: reason)
      get question_path(question)

      assert_select "[role=note] strong", title
      assert_select "[role=note] code", reason
      assert_select "a[href=?]", new_question_path(text: "How much paid leave do I get?"), "Ask again"
      assert_select "span", "A narrower question usually gets a complete answer."
    end
  end

  test "show offers Try again on a failed question, without the error outside development" do
    question = asked(status: :failed, error: "Answering provider 529: Overloaded")

    get question_path(question)

    assert_select "h2", "Citewise couldn't answer this question"
    assert_select "form[action=?][method=post] input[name='question[text]'][value=?]", questions_path, "How much leave?"
    assert_select "form button", "Try again"
    assert_select "details", count: 0
    assert_not_includes response.body, "Overloaded"
  end

  test "show includes a failed question's error in development" do
    question = asked(status: :failed, error: "Answering provider 529: Overloaded")

    stub(Rails, :env, -> { ActiveSupport::EnvironmentInquirer.new("development") }) { get question_path(question) }

    assert_select "details code", "Answering provider 529: Overloaded"
  end

  test "Try again creates a new question with the same text" do
    failed = Question.create!(text: "How much leave?", status: :failed, error: "boom")

    post questions_path, params: { question: { text: failed.text } }

    assert_redirected_to question_path(Question.last)
    assert_not_equal failed, Question.last
    assert failed.reload.failed?
  end

  test "show words a question the sweep failed as timed out" do
    question = asked(created_at: 2.hours.ago)
    Question.fail_abandoned

    get question_path(question)

    assert_select "h2", "This question timed out"
    assert_select "form button", "Try again"
  end

  test "show treats an answered question with no sources as a dead end" do
    question = asked(text: "Parental leave?", status: :answered, answer: Answering::AskService::NO_SOURCES_ANSWER)

    get question_path(question)

    assert_select "h2", "No matching passages"
    assert_select "a[href=?]", new_question_path(text: "Parental leave?"), "Edit question"
    assert_select "article[aria-label=Answer] p", text: Answering::AskService::NO_SOURCES_ANSWER, count: 0
  end

  test "show renders the page when a Turbo form submission follows the redirect to it" do
    question = asked

    # Turbo's form fetch asks for streams first, and keeps that Accept header across the redirect.
    get question_path(question), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "h1", "How much leave?"
  end

  test "the turbo_stream refresh is empty while pending, and replaces the answer once it isn't" do
    question = asked

    get answer_question_path(question, format: :turbo_stream)
    assert_response :no_content

    question.update!(status: :failed, error: "boom")
    get answer_question_path(question, format: :turbo_stream)

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=?] template h2", dom_id(question, :answer), "Citewise couldn't answer this question"
    assert_select "turbo-stream[action=update][target=?] template", dom_id(question, :status), "Citewise couldn't answer this question."
  end

  test "show and answer return 404 for a question this visitor didn't ask" do
    question = Question.create!(text: "My manager is making me miserable")

    get question_path(question)
    assert_unavailable
    assert_not_includes response.body, "My manager is making me miserable"

    get answer_question_path(question, format: :turbo_stream)
    assert_response :not_found
    assert_empty response.body
  end

  test "another visitor can't see a question by its link" do
    question = asked

    open_session do |visitor|
      visitor.get question_path(question)
      visitor.assert_response :not_found
      visitor.assert_select "h1", "This question isn't available"
    end
  end

  test "a question that doesn't exist gets the same page" do
    get question_path(id: 0)

    assert_unavailable
  end

  test "the unavailable page is HTML even when the request asks for streams first" do
    get question_path(id: 0), headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }

    assert_unavailable
  end

  test "a visitor can still see their earlier questions after asking another" do
    first = asked
    asked(text: "Can I work remotely?")

    get question_path(first)

    assert_response :success
    assert_select "h1", "How much leave?"
  end

  test "the routes return 404 when the ask page is disabled" do
    question = Question.create!(text: "How much leave?")
    Rails.configuration.x.ask_page[:enabled] = false

    get root_path
    assert_response :not_found
    get new_question_path
    assert_response :not_found
    get question_path(question)
    assert_response :not_found
    assert_no_difference -> { Question.count } do
      post questions_path, params: { question: { text: "How much leave?" } }
    end
    assert_response :not_found
  ensure
    Rails.configuration.x.ask_page[:enabled] = true
  end

  private
    def assert_unavailable
      assert_response :not_found
      assert_equal "text/html", response.media_type
      assert_select "h1", "This question isn't available"
      assert_select "main a[href=?]", new_question_path, "Ask a question"
    end

    def ask(ip:)
      post questions_path, params: { question: { text: "How much leave?" } }, env: { "REMOTE_ADDR" => ip }
    end

    # Asks through the app, so the question is this session's to see, then sets its state.
    def asked(text: "How much leave?", **attributes)
      post questions_path, params: { question: { text: text } }
      Question.last.tap { it.update!(attributes) }
    end

    def answered_question(answer: ANSWER, cited_text: chunks(:leave).content, stop_reason: "end_turn")
      cited = answer.split(" Ask HR").first
      asked(
        text: "How much paid leave do I get?", status: :answered, answer: answer, stop_reason: stop_reason, retrieval_ms: 300, answer_ms: 1200,
        retrieval: [ { chunk_id: chunks(:leave).id, rank: 1 } ],
        citations: [ { chunk_id: chunks(:leave).id, cited_text: cited_text, answer_start: 0, answer_end: cited.length,
                       document_title: "Employee Handbook", source_title: "Employee Handbook > Benefits > Paid leave" } ]
      )
    end
end
