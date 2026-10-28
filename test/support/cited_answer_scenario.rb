require_relative "fake_answerer"

# An answer, for browser tests, that cites three sources. Source 2 has two passages, and
# source 3's passage has a table, an external link, a relative link, an image, and raw
# HTML. Each sentence has one citation, so a sentence's index is its citation id.
module CitedAnswerScenario
  LEAVE = "Full-time employees accrue 20 days of paid leave per year."
  CARRY_OVER = "Up to 5 unused days carry over into the next year."
  BOOKING = "Book leave in the HR portal at least two weeks ahead."
  PART_TIME = "Part-time employees accrue leave pro rata, by the hours in their contract."
  SENTENCES = [ LEAVE, CARRY_OVER, BOOKING, PART_TIME ].freeze
  ANSWER = "#{LEAVE} #{CARRY_OVER} #{BOOKING}\n\n#{PART_TIME}".freeze

  PART_TIME_PASSAGE = <<~MARKDOWN.chomp.freeze
    Part-time employees accrue leave pro rata. Try [the leave calculator](https://example.com/leave-calculator) or read [the handbook](/handbook/part-time).

    | Hours per week | Days per year |
    | --- | --- |
    | 20 | 10 |
    | 30 | 15 |

    ![Leave by hours chart](https://example.com/leave-by-hours.png)

    <div onclick="alert('raw')">Raw HTML block</div>
  MARKDOWN

  private
    def ask_cited_question
      ask "How much paid leave do I get?"
      assert_subscribed_to_answer
      answer_cited_question
      assert_selector "[data-question-status=answered] [data-controller=citations]"
    end

    # Answers the questions asked so far with ANSWER. Every cited chunk gets an embedding,
    # so retrieval returns them all.
    def answer_cited_question
      part_time = create_part_time_chunk
      [ chunks(:leave_details), part_time ].each do |chunk|
        ChunkEmbedding.create!(chunk: chunk, model: "voyage-4-lite", strategy: :raw, dimensions: 1024,
                               embedding: FakeEmbedder.new.vector_for(chunk.content), input_hash: chunk.id.to_s)
      end
      # leave_details' carry-over and booking paragraphs are separate passages of one source.
      carry_over, booking = Chunking::Paragraphs.split(chunks(:leave_details).content).grep(/Carry-over|Booking leave/)
      citations = [ citation(LEAVE, chunks(:leave), chunks(:leave).content), citation(CARRY_OVER, chunks(:leave_details), carry_over),
                    citation(BOOKING, chunks(:leave_details), booking), citation(PART_TIME, part_time, PART_TIME_PASSAGE) ]
      answer_questions FakeAnswerer.new(text: ANSWER, citations: citations)
    end

    def create_part_time_chunk
      guide = Document.create!(title: "Part-time Guide", source_type: :filesystem, source_uri: "guides/part-time.md",
                               content_hash: Digest::SHA256.hexdigest(PART_TIME_PASSAGE), ingestion_status: :ingested, ingested_at: 1.day.ago)
      Chunk.create!(document: guide, position: 0, content: PART_TIME_PASSAGE, heading_path: [ "Part-time Guide", "Accrual" ],
                    token_count: 80, content_hash: Digest::SHA256.hexdigest(PART_TIME_PASSAGE))
    end

    def citation(sentence, chunk, passage)
      start = ANSWER.index(sentence)
      { chunk_id: chunk.id, cited_text: passage, answer_start: start, answer_end: start + sentence.length }
    end

    def marker_after(sentence)
      find("a[data-citations-target=marker][data-citation-ids='#{SENTENCES.index(sentence)}']")
    end

    def card_button(number)
      find("#source-#{number} [data-citations-target=cardButton]")
    end

    def assert_highlighted(*sentences)
      assert_selector "span[data-highlighted]", count: sentences.size
      assert_equal sentences, all("span[data-highlighted]").map(&:text)
    end

    # Only one passage shows "Cited here": the one that starts with text.
    def assert_cited_here(text)
      assert_selector "blockquote", text: "Cited here", count: 1
      assert_selector "blockquote", text: /Cited here\s+#{Regexp.escape(text)}/
    end

    def assert_expanded(*states)
      assert_equal states, all("[data-citations-target=cardButton]", count: states.size).map { it["aria-expanded"] == "true" }
    end

    def assert_sheet_closed
      assert_selector "#source-sheet:not([open])", visible: :all
    end

    # A ResizeObserver sets the padding, so this waits for it.
    def assert_padded_for_sheet
      page.document.synchronize do
        padding, height = evaluate_script(<<~JS)
          [ parseFloat(getComputedStyle(document.querySelector("[data-controller=citations]")).paddingBottom),
            document.getElementById("source-sheet").offsetHeight ]
        JS
        raise Capybara::ExpectationNotMet, "#{padding}px of padding under a #{height}px sheet" unless height > 0 && padding >= height
      end
    end

    # The rail flow, shared with the WebKit desktop check.
    def assert_marker_selects_its_source_in_the_rail
      url = current_url
      marker_after(BOOKING).click

      assert_selector "#source-2[data-selected]"
      assert_expanded false, true, false
      assert_highlighted CARRY_OVER, BOOKING
      assert_cited_here "Booking leave"
      assert_equal url, current_url
    end

    # The sheet flow, shared with the Android check.
    def assert_marker_opens_the_sheet_until_escape
      tap_on marker_after(CARRY_OVER)
      assert_selector "#source-sheet-title:focus", text: "Leave Policy"
      assert_highlighted CARRY_OVER

      send_keys :escape

      assert_sheet_closed
      assert_selector "a[data-citation-ids='1']:focus"
      assert_highlighted
    end

    # A touch tap, where the device has touch.
    def tap_on(element)
      element.with_playwright_element_handle(&:tap_point)
    end
end
