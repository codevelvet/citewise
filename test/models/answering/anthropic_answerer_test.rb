require "test_helper"

class Answering::AnthropicAnswererTest < ActiveSupport::TestCase
  ENDPOINT = "https://api.anthropic.com/v1/messages"
  QUESTION = "How much paid leave do I get?"

  setup do
    config = Rails.configuration.x.answering
    # No SDK retries, so error stubs are hit once and the tests don't sleep.
    @answerer = Answering::AnthropicAnswerer.new(model: config[:model], max_tokens: config[:max_tokens], max_retries: 0,
                                                 api_key: ENV.fetch("ANTHROPIC_API_KEY", "test-key"))
    @chunks = [ chunks(:leave), chunks(:intro) ]
  end

  test "is the default answerer, with model, max_tokens, and max_retries from app configuration" do
    answerer = Answering::Answerer.default
    assert_instance_of Answering::AnthropicAnswerer, answerer
    assert_equal "claude-haiku-4-5", answerer.model
    assert_equal 1024, answerer.instance_variable_get(:@max_tokens)
    assert_equal 2, answerer.instance_variable_get(:@client).max_retries
  end

  test "answers from search results with native citations mapped to chunk ids, logging token usage" do
    log = StringIO.new
    answer = with_logger(log) do
      VCR.use_cassette("anthropic_answerer", match_requests_on: %i[method uri body]) { @answerer.answer(QUESTION, @chunks) }
    end

    assert_requested :post, ENDPOINT, body: hash_including(
      model: "claude-haiku-4-5",
      max_tokens: 1024,
      system: [ { type: "text", text: Answering::Answerer::SYSTEM_PROMPT, cache_control: { type: "ephemeral" } } ],
      messages: [ { role: "user", content: [
        search_result(chunks(:leave), "Employee Handbook > Benefits > Paid leave"),
        search_result(chunks(:intro), "Employee Handbook > Introduction"),
        { type: "text", text: QUESTION }
      ] } ]
    )
    assert_match(/20 days/, answer.text)
    assert_equal "claude-haiku-4-5", answer.model
    assert answer.citations.any?
    answer.citations.each do |citation|
      assert_equal chunks(:leave).id, citation[:chunk_id]
      assert_includes chunks(:leave).content, citation[:cited_text].strip
      assert_operator answer.text[citation[:answer_start]...citation[:answer_end]].length, :>, 0
    end
    assert_equal %i[cache_read_tokens cache_write_tokens input_tokens output_tokens], answer.usage.keys.sort
    assert answer.usage[:input_tokens].positive?
    assert_match(/Claude answer model=claude-haiku-4-5 input_tokens=\d+ output_tokens=\d+ cache_read_tokens=\d+ cache_write_tokens=\d+ citations=\d+ dropped=0/, log.string)
  end

  test "citation positions cover the text block each citation is attached to" do
    stub_claude(content: [
      text_block("Full-time employees get "),
      text_block("20 days of paid leave per year", citations: [ citation(chunks(:leave)) ]),
      text_block(", and "),
      text_block("the handbook explains how we work", citations: [ citation(chunks(:intro)), citation(chunks(:leave)) ]),
      text_block(".")
    ])

    answer = @answerer.answer(QUESTION, @chunks)

    assert_equal "Full-time employees get 20 days of paid leave per year, and the handbook explains how we work.", answer.text
    spans = answer.citations.map { [ it[:chunk_id], answer.text[it[:answer_start]...it[:answer_end]] ] }
    assert_equal [
      [ chunks(:leave).id, "20 days of paid leave per year" ],
      [ chunks(:intro).id, "the handbook explains how we work" ],
      [ chunks(:leave).id, "the handbook explains how we work" ]
    ], spans
    assert_equal chunks(:leave).content, answer.citations.first[:cited_text]
  end

  test "a citation that doesn't name a retrieved chunk is dropped and logged" do
    stub_claude(content: [ text_block("20 days.", citations: [ citation(chunks(:leave)), citation(nil, source: "chunk:999999"), citation(nil, source: "elsewhere") ]) ])

    log = StringIO.new
    answer = with_logger(log) { @answerer.answer(QUESTION, @chunks) }

    assert_equal [ chunks(:leave).id ], answer.citations.map { it[:chunk_id] }
    assert_includes log.string, %(Claude citation dropped: source "chunk:999999" is not a retrieved chunk)
    assert_includes log.string, %(Claude citation dropped: source "elsewhere" is not a retrieved chunk)
    assert_includes log.string, "citations=1 dropped=2"
  end

  test "an answer without citations has an empty list" do
    stub_claude(content: [ text_block("The documents don't cover parental leave.") ])

    answer = @answerer.answer("What is the parental leave policy?", @chunks)

    assert_equal "The documents don't cover parental leave.", answer.text
    assert_equal [], answer.citations
  end

  test "reports cache usage" do
    stub_claude(content: [ text_block("20 days.") ], usage: { input_tokens: 50, output_tokens: 5, cache_read_input_tokens: 4100, cache_creation_input_tokens: 0 })

    assert_equal({ input_tokens: 50, output_tokens: 5, cache_read_tokens: 4100, cache_write_tokens: 0 }, @answerer.answer(QUESTION, @chunks).usage)
  end

  test "rate limits are transient and carry Retry-After" do
    stub_error(429, "rate_limit_error", "Number of request tokens has exceeded your per-minute rate limit", headers: { "retry-after" => "12" })

    error = assert_raises(Answering::Answerer::TransientError) { @answerer.answer(QUESTION, @chunks) }
    assert_equal 12.0, error.retry_after
    assert_includes error.message, "Claude 429"
  end

  test "overloaded and server errors, and timeouts, are transient" do
    [ [ 529, "overloaded_error" ], [ 503, "api_error" ], [ 500, "api_error" ] ].each do |status, type|
      stub_error(status, type, "Try again")
      error = assert_raises(Answering::Answerer::TransientError) { @answerer.answer(QUESTION, @chunks) }
      assert_includes error.message, "Claude #{status}"
    end

    stub_request(:post, ENDPOINT).to_timeout
    assert_raises(Answering::Answerer::TransientError) { @answerer.answer(QUESTION, @chunks) }
  end

  test "invalid requests and authentication failures are permanent" do
    { 400 => "invalid_request_error", 401 => "authentication_error", 403 => "permission_error", 404 => "not_found_error" }.each do |status, type|
      stub_error(status, type, "Nope")
      error = assert_raises(Answering::Answerer::PermanentError) { @answerer.answer(QUESTION, @chunks) }
      assert_includes error.message, "Claude #{status}"
    end
  end

  test "never reaches the network unstubbed" do
    # VCR (hooked into WebMock) refuses the request. The SDK rescues that like any
    # connection failure, so it surfaces as transient with VCR's error as the root cause.
    # A missing stub or a cassette mismatch looks like this too.
    error = assert_raises(Answering::Answerer::TransientError) { @answerer.answer(QUESTION, @chunks) }
    assert_instance_of Anthropic::Errors::APIConnectionError, error.cause
    assert_instance_of VCR::Errors::UnhandledHTTPRequestError, error.cause.cause
  end

  private
    def search_result(chunk, title)
      { type: "search_result", source: "chunk:#{chunk.id}", title: title, content: [ { type: "text", text: chunk.content } ], citations: { enabled: true } }
    end

    def text_block(text, citations: nil)
      { type: "text", text: text, citations: citations }
    end

    def citation(chunk, source: "chunk:#{chunk.id}")
      { type: "search_result_location", source: source, title: chunk&.source_title, cited_text: chunk&.content || "Text.",
        search_result_index: 0, start_block_index: 0, end_block_index: 1 }
    end

    def stub_claude(content:, usage: { input_tokens: 300, output_tokens: 20, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 })
      body = { id: "msg_test", type: "message", role: "assistant", model: "claude-haiku-4-5", content: content,
               stop_reason: "end_turn", stop_sequence: nil, usage: usage }
      stub_request(:post, ENDPOINT).to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def stub_error(status, type, message, headers: {})
      body = { type: "error", error: { type: type, message: message } }
      stub_request(:post, ENDPOINT).to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" }.merge(headers))
    end

    def with_logger(io)
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      yield
    ensure
      Rails.logger = original
    end
end
