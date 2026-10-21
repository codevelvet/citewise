module Answering
  # Answers with Claude's native citations. Each chunk is sent as a search-result
  # content block whose source is "chunk:<id>", so every citation Claude returns
  # names the chunk it quotes. Its content is one text block per paragraph
  # (Chunking::Paragraphs), so a citation covers only the paragraphs it uses.
  class AnthropicAnswerer < Answerer
    SOURCE = /\Achunk:(\d+)\z/

    def initialize(model:, max_tokens:, max_retries:, api_key: ENV.fetch("ANTHROPIC_API_KEY") { Rails.application.credentials.dig(:anthropic, :api_key) })
      super(model: model)
      @max_tokens = max_tokens
      @client = Anthropic::Client.new(api_key: api_key, max_retries: max_retries)
    end

    def answer(text, chunks)
      message = @client.messages.create(
        model: model,
        max_tokens: @max_tokens,
        # No cache breakpoint: the system prompt is far below the model's caching
        # minimum (4096 tokens on Haiku 4.5), and the chunks after it change with
        # every question. Add one when there's a large prefix that stays the same.
        system_: [ { type: "text", text: SYSTEM_PROMPT } ],
        messages: [ { role: "user", content: chunks.map { search_result(it) } + [ { type: "text", text: text } ] } ]
      )

      answer_text, citations, dropped = read(message, chunks.index_by(&:id).transform_values { Chunking::Paragraphs.split(it.content) })
      usage = usage_of(message)
      Rails.logger.info "Claude answer model=#{model} input_tokens=#{usage[:input_tokens]} output_tokens=#{usage[:output_tokens]} " \
        "cache_read_tokens=#{usage[:cache_read_tokens]} cache_write_tokens=#{usage[:cache_write_tokens]} " \
        "citations=#{citations.size} dropped=#{dropped} stop_reason=#{message.stop_reason}"

      Answer.new(text: answer_text, citations: citations, model: model, usage: usage, stop_reason: message.stop_reason.to_s)
    rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError, Anthropic::Errors::ConflictError => error
      raise TransientError.new("Claude #{error.status}: #{error.message}", retry_after: retry_after(error.headers))
    rescue Anthropic::Errors::APIConnectionError => error
      raise TransientError, "Claude #{error.class.name.demodulize}: #{error.message}"
    rescue Anthropic::Errors::Error => error
      raise PermanentError, "Claude #{error.try(:status) || error.class.name.demodulize}: #{error.message}"
    end

    private
      def search_result(chunk)
        {
          type: "search_result",
          source: "chunk:#{chunk.id}",
          title: chunk.source_title,
          content: Chunking::Paragraphs.split(chunk.content).map { { type: "text", text: it } },
          citations: { enabled: true }
        }
      end

      # Joins the text blocks into the answer. A citation supports the text block
      # it's attached to, so its span is that block's offsets in the answer. Its
      # cited_text is rebuilt from the paragraphs it cites, so it's always an
      # exact passage of the chunk's content.
      def read(message, paragraphs_by_chunk_id)
        answer_text = +""
        citations = []
        dropped = 0

        message.content.each do |block|
          next unless block.type == :text

          start = answer_text.length
          answer_text << block.text
          Array(block.citations).each do |citation|
            chunk_id = citation.try(:source).to_s[SOURCE, 1]&.to_i
            paragraphs = paragraphs_by_chunk_id[chunk_id]
            block_start, block_end = citation.try(:start_block_index), citation.try(:end_block_index)
            if paragraphs.nil?
              dropped += 1
              Rails.logger.warn "Claude citation dropped: source #{citation.try(:source).inspect} is not a retrieved chunk"
            elsif !(0...paragraphs.size).cover?(block_start) || !(block_start + 1..paragraphs.size).cover?(block_end)
              dropped += 1
              Rails.logger.warn "Claude citation dropped: blocks #{block_start.inspect}...#{block_end.inspect} aren't in chunk:#{chunk_id}'s #{paragraphs.size}"
            else
              citations << { chunk_id: chunk_id, cited_text: paragraphs[block_start...block_end].join("\n\n"),
                             block_start: block_start, block_end: block_end, answer_start: start, answer_end: answer_text.length }
            end
          end
        end

        [ answer_text, citations, dropped ]
      end

      def usage_of(message)
        usage = message.usage
        {
          input_tokens: usage.input_tokens,
          output_tokens: usage.output_tokens,
          cache_read_tokens: usage.cache_read_input_tokens.to_i,
          cache_write_tokens: usage.cache_creation_input_tokens.to_i
        }
      end

      def retry_after(headers)
        Float(headers&.[]("retry-after"), exception: false)
      end
  end
end
