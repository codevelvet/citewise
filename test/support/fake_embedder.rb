# Returns deterministic vectors without the network: the same text always gets
# the same vector. Records each batch it was given, and raises #error if set.
class FakeEmbedder < Embeddings::Embedder
  attr_reader :batches
  attr_accessor :error

  def initialize(model: "voyage-4-lite", dimensions: 1024)
    super
    @batches = []
  end

  def embed_documents(texts)
    raise error if error
    batches << texts
    texts.map { vector_for(it) }
  end

  def embed_query(text)
    raise error if error
    vector_for(text)
  end

  def vector_for(text)
    random = Random.new(Digest::SHA256.hexdigest(text).to_i(16))
    Array.new(dimensions) { random.rand(-1.0..1.0) }
  end

  # Makes Embedder.default return a FakeEmbedder, and RateLimiter.default never wait, inside the block.
  module TestHelper
    def with_fake_embedder(embedder = FakeEmbedder.new)
      unlimited = Embeddings::RateLimiter.new(requests_per_minute: Float::INFINITY, tokens_per_minute: Float::INFINITY)
      stub_singleton(Embeddings::Embedder, :default, embedder) do
        stub_singleton(Embeddings::RateLimiter, :default, unlimited) { yield embedder }
      end
    end

    private
      def stub_singleton(object, name, value)
        original = object.method(name)
        object.define_singleton_method(name) { value }
        yield
      ensure
        object.define_singleton_method(name, original)
      end
  end
end
