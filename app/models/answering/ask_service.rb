module Answering
  # Answers a question from the indexed chunks and records it as a Question.
  #
  #   question = Answering::AskService.call("How much paid leave do I get?")
  #   question.answer    # => "Full-time employees accrue 20 days of paid leave per year."
  #   question.citations # => [ { "chunk_id" => 12, "cited_text" => "...", "answer_start" => 0, ... } ]
  #
  # Synchronous: one embedding call and one Claude call. Retrieval and
  # citations store snapshots of their chunks, because re-ingesting a document
  # deletes its chunks. When either call fails, the Question is saved as failed
  # and the error is re-raised, so the caller can decide whether to retry.
  class AskService
    def self.call(text, retriever: Retrieval::Retriever.new, answerer: Answerer.default)
      new(retriever: retriever, answerer: answerer).call(text)
    end

    def initialize(retriever:, answerer:)
      @retriever = retriever
      @answerer = answerer
    end

    def call(text)
      question = Question.create!(text: text, model: @answerer.model)

      results, retrieval_ms = timed { @retriever.call(text) }
      question.update!(retrieval: results.map { retrieved(it) }, retrieval_ms: retrieval_ms)

      answer, answer_ms = timed { @answerer.answer(text, results.map(&:chunk)) }
      chunks = results.map(&:chunk).index_by(&:id)
      question.update!(
        status: :answered, answer: answer.text, model: answer.model, answer_ms: answer_ms,
        citations: answer.citations.map { it.merge(source_of(chunks.fetch(it[:chunk_id]))) },
        **answer.usage.slice(:input_tokens, :output_tokens, :cache_read_tokens, :cache_write_tokens)
      )
      question
    rescue Embeddings::Embedder::Error, Answerer::Error => error
      question&.update!(status: :failed, error: error.message)
      raise
    end

    private
      def retrieved(result)
        { chunk_id: result.chunk.id, rank: result.rank, similarity: result.similarity, **source_of(result.chunk), content: result.chunk.content }
      end

      def source_of(chunk)
        { document_id: chunk.document_id, document_title: chunk.document.title, source_title: chunk.source_title }
      end

      def timed
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        [ result, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round ]
      end
  end
end
