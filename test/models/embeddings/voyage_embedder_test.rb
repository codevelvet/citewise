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
end
