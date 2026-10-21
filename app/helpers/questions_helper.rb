module QuestionsHelper
  # Plain-language wording for an incomplete answer's stop reason: [ title, explanation ].
  INCOMPLETE_NOTICES = {
    "max_tokens" => [ "This answer was cut off", "It reached the length limit before it finished, so it may leave things out. What is here is cited as usual." ],
    "refusal" => [ "This answer stopped early", "The answering model declined to continue, so the answer may be partial or empty. What is here is cited as usual." ],
    "model_context_window_exceeded" => [ "This answer was cut off", "The question and its sources were too long to finish an answer, so it may leave things out." ],
    "missing" => [ "This answer may be incomplete", "Citewise could not confirm that the answer finished, so it may leave things out." ]
  }.freeze
  INCOMPLETE_NOTICE = [ "This answer stopped early", "It stopped before finishing, so it may be incomplete." ].freeze

  def incomplete_notice(question)
    INCOMPLETE_NOTICES.fetch(question.stop_reason, INCOMPLETE_NOTICE)
  end

  # The muted line under the question.
  def question_meta(question)
    if question.answered?
      seconds = (question.retrieval_ms.to_i + question.answer_ms.to_i) / 1000.0
      sources = question.cited_answer.sources.size
      "Answered in #{number_with_precision(seconds, precision: 1)} seconds · #{pluralize(sources, "source")}"
    else
      "Asked #{time_ago_in_words(question.created_at)} ago"
    end
  end

  # Announced by the page's live region when the answer section is replaced.
  def answer_status_message(question)
    if question.pending? then ""
    elsif question.abandoned? then "This question timed out."
    elsif question.failed? then "Citewise couldn't answer this question."
    elsif question.retrieval.empty? then "No matching passages were found."
    elsif question.incomplete? then "The answer is ready, but it may be incomplete."
    else "The answer is ready."
    end
  end

  # One answer paragraph: escaped text, each cited span wrapped with the citations that
  # support it, and a marker linking to its source card. Built without whitespace between
  # parts, since paragraphs keep their line breaks.
  def cited_paragraph(parts)
    safe_join(parts.map do |part|
      case part
      when Question::CitedAnswer::Marker
        link_to part.number, "#source-#{part.number}", aria: { label: "Source #{part.number}" }, data: { source_number: part.number },
          class: "mx-0.5 inline-flex h-6 min-w-6 items-center justify-center rounded-md border border-marker-line bg-marker px-1.5 " \
                 "align-[3px] font-sans text-xs leading-none font-semibold text-marker-ink no-underline hover:border-link"
      when ->(text) { text.citation_ids.any? }
        tag.span part.text, data: { citation_ids: part.citation_ids.join(" "), source_numbers: part.numbers.join(" ") }
      else
        part.text
      end
    end)
  end
end
