require "test_helper"

class Embeddings::VoyageEmbedderTest < ActiveSupport::TestCase
  ENDPOINT = "https://ai.mongodb.com/v1/embeddings"

  setup do
    config = Rails.configuration.x.embeddings
    @embedder = Embeddings::VoyageEmbedder.new(model: config[:model], dimensions: config[:dimensions], base_url: config[:base_url], api_key: ENV.fetch("VOYAGE_API_KEY", "test-key"))
  end

  test "is the default embedder, with model and dimensions from app configuration" do
    embedder = Embeddings::Embedder.default
    assert_instance_of Embeddings::VoyageEmbedder, embedder
    assert_equal [ "voyage-4-lite", 1024 ], [ embedder.model, embedder.dimensions ]
  end

  test "embeds documents and queries with their own input types, logging Voyage's token usage" do
    documents = [ "Employee Handbook > Benefits > Paid leave\n\nFull-time employees accrue 20 days of paid leave per year.",
                  "Employee Handbook > Introduction\n\nWelcome to the company. This handbook explains how we work." ]
    log = StringIO.new
    vectors = query = nil

    with_logger(log) do
      VCR.use_cassette("voyage_embedder", match_requests_on: %i[method uri body]) do
        vectors = @embedder.embed_documents(documents)
        query = @embedder.embed_query("How much paid leave do I get?")
      end
    end

    assert_equal 2, vectors.size
    assert vectors.all? { it.size == 1024 && it.all?(Float) }
    assert_equal 1024, query.size
    assert_requested :post, ENDPOINT, body: hash_including(model: "voyage-4-lite", input_type: "document", output_dimension: 1024, input: documents)
    assert_requested :post, ENDPOINT, body: hash_including(input_type: "query", input: [ "How much paid leave do I get?" ])
    assert_match(/Voyage embed model=voyage-4-lite input_type=document inputs=2 total_tokens=\d+/, log.string)
    assert_match(/Voyage embed model=voyage-4-lite input_type=query inputs=1 total_tokens=\d+/, log.string)
  end

  test "a rate limit is transient and carries Retry-After" do
    stub_voyage(status: 429, detail: "Rate limit exceeded", headers: { "Retry-After" => "7" })

    error = assert_raises(Embeddings::Embedder::TransientError) { @embedder.embed_documents([ "text" ]) }
    assert_equal 7.0, error.retry_after
    assert_includes error.message, "Voyage 429: Rate limit exceeded"
  end

  test "a rate limit with an HTTP-date Retry-After waits until then" do
    freeze_time do
      stub_voyage(status: 429, detail: "Slow down", headers: { "Retry-After" => 30.seconds.from_now.httpdate })

      error = assert_raises(Embeddings::Embedder::TransientError) { @embedder.embed_documents([ "text" ]) }
      assert_in_delta 30, error.retry_after, 1
    end
  end

  test "server errors and timeouts are transient" do
    stub_voyage(status: 503, detail: "Service unavailable")
    error = assert_raises(Embeddings::Embedder::TransientError) { @embedder.embed_documents([ "text" ]) }
    assert_nil error.retry_after

    stub_request(:post, ENDPOINT).to_timeout
    assert_raises(Embeddings::Embedder::TransientError) { @embedder.embed_documents([ "text" ]) }
  end

  test "authentication failures are permanent and carry Voyage's detail" do
    { 401 => "Provided API key is invalid.", 403 => "API key is not authorized for this host." }.each do |status, detail|
      stub_voyage(status: status, detail: detail)

      error = assert_raises(Embeddings::Embedder::PermanentError) { @embedder.embed_documents([ "text" ]) }
      assert_equal "Voyage #{status}: #{detail}", error.message
    end
  end

  test "invalid requests are permanent" do
    stub_voyage(status: 400, detail: "Value 'x' supplied for argument 'output_dimension' is not valid.")
    assert_raises(Embeddings::Embedder::PermanentError) { @embedder.embed_documents([ "text" ]) }
  end

  private
    def stub_voyage(status:, detail:, headers: {})
      stub_request(:post, ENDPOINT).to_return(status: status, body: { detail: detail }.to_json, headers: { "Content-Type" => "application/json" }.merge(headers))
    end

    def with_logger(io)
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      yield
    ensure
      Rails.logger = original
    end
end
