require_relative "fake_embedder"

# Answers without the network: by default the whole answer cites the first chunk.
# Records each call, and raises #error if set.
class FakeAnswerer < Answering::Answerer
  USAGE = { input_tokens: 900, output_tokens: 40, cache_read_tokens: 0, cache_write_tokens: 0 }.freeze

  attr_reader :calls
  attr_accessor :error, :text, :cite, :stop_reason

  def initialize(model: "claude-haiku-4-5", text: "Full-time employees accrue 20 days of paid leave per year.", cite: true, stop_reason: "end_turn")
    super(model: model)
    @text = text
    @cite = cite
    @stop_reason = stop_reason
    @calls = []
  end

  def answer(question, chunks)
    raise error if error
    calls << [ question, chunks ]

    citations = []
    if cite && chunks.any?
      paragraphs = Chunking::Paragraphs.split(chunks.first.content)
      citations << { chunk_id: chunks.first.id, cited_text: paragraphs.join("\n\n"), block_start: 0, block_end: paragraphs.size,
                     answer_start: 0, answer_end: text.length }
    end
    Answer.new(text: text, citations: citations, model: model, usage: USAGE, stop_reason: stop_reason)
  end

  # Makes Answerer.default return a FakeAnswerer inside the block. Includes
  # FakeEmbedder::TestHelper, since asking a question also embeds it.
  module TestHelper
    include FakeEmbedder::TestHelper

    def with_fake_answerer(answerer = FakeAnswerer.new)
      stub_singleton(Answering::Answerer, :default, answerer) { yield answerer }
    end
  end
end
