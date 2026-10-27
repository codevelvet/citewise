class Question
  # Places citation markers in an answer, and gathers one source per cited chunk.
  #
  #   cited = Question::CitedAnswer.new(question.answer, question.citations)
  #   cited.paragraphs # => [ [ Text("Full-time employees accrue 20 days.", citation_ids: [0], numbers: [1]), Marker(1) ], ... ]
  #   cited.sources    # => [ Source(number: 1, document_title: "Employee Handbook", source_title: "...", passages: [ Passage(...) ]) ]
  #
  # Each cited chunk gets a number by first use, so the numbers match places in the
  # documents. A marker goes after each cited span; a span cited by several chunks
  # shows each distinct number once. Citation ids are indexes into citations.
  #
  # Offsets are String#length indexes into the answer (Answering::Answerer). Paragraphs
  # are separated by blank lines; a span that crosses one is split at the break. Text
  # is never marked safe: the view escapes every part.
  class CitedAnswer
    # citation_ids is empty for uncited text.
    Text = Data.define(:text, :citation_ids, :numbers)
    Marker = Data.define(:number)
    # text is the cited Markdown, for PassageRenderer.
    Passage = Data.define(:citation_ids, :text)
    Source = Data.define(:number, :document_title, :source_title, :passages)

    PARAGRAPH_BREAK = /\n[ \t]*\n\s*/

    Span = Data.define(:id, :chunk_id, :start, :stop)

    attr_reader :paragraphs, :sources

    def initialize(answer, citations)
      @answer = answer.to_s
      @citations = citations
      @spans = citations.each_with_index.map { |citation, id| span(citation, id) }
      @numbers = number_chunks
      @sources = gather_sources
      @paragraphs = split_paragraphs
    end

    def cited? = @citations.any?

    private
      # The span stops before trailing whitespace, so its marker follows the sentence.
      def span(citation, id)
        start = citation["answer_start"].to_i.clamp(0, @answer.length)
        stop = citation["answer_end"].to_i.clamp(start, @answer.length)
        stop = start + @answer[start...stop].rstrip.length
        Span.new(id: id, chunk_id: citation["chunk_id"], start: start, stop: stop)
      end

      def number_chunks
        @spans.sort_by { [ it.start, it.id ] }.each_with_object({}) do |span, numbers|
          numbers[span.chunk_id] ||= numbers.size + 1
        end
      end

      def gather_sources
        @citations.each_with_index.group_by { |citation, _| citation["chunk_id"] }.map do |chunk_id, cited|
          first, _ = cited.first
          passages = cited.group_by { |citation, _| citation["cited_text"].to_s }.map do |text, same|
            Passage.new(citation_ids: same.map(&:last), text: text.strip)
          end
          Source.new(number: @numbers.fetch(chunk_id), document_title: first["document_title"], source_title: first["source_title"], passages: passages)
        end.sort_by(&:number)
      end

      def split_paragraphs
        ranges = paragraph_ranges
        return [] if ranges.empty?

        markers = Hash.new { |hash, key| hash[key] = [] }
        @spans.each do |span|
          range = ranges.find { it.cover?(span.stop) } || ranges.reverse.find { it.end <= span.stop } || ranges.first
          markers[span.stop.clamp(range.begin, range.end)] << @numbers.fetch(span.chunk_id)
        end

        ranges.map { |range| parts_of(range, markers) }
      end

      # Offsets of the text between blank lines, as begin..end with end exclusive for
      # the text and inclusive for markers, which may follow the paragraph's last character.
      def paragraph_ranges
        ranges = []
        position = @answer[/\A\s*/].length
        @answer.scan(PARAGRAPH_BREAK) do
          match = Regexp.last_match
          next if match.begin(0) < position

          ranges << (position..match.begin(0)) if match.begin(0) > position
          position = match.end(0)
        end
        ranges << (position..@answer.rstrip.length) if @answer.rstrip.length > position
        ranges
      end

      def parts_of(range, markers)
        edges = @spans.flat_map { [ it.start, it.stop ] }.select { range.begin < it && it < range.end }
        points = [ range.begin, *edges, range.end ].uniq.sort

        parts = marker_parts(markers[range.begin])
        points.each_cons(2) do |from, to|
          covering = @spans.select { it.start <= from && it.stop >= to }
          parts << Text.new(text: @answer[from...to], citation_ids: covering.map(&:id), numbers: covering.map { @numbers.fetch(it.chunk_id) }.uniq.sort)
          parts.concat(marker_parts(markers[to]))
        end
        parts
      end

      def marker_parts(numbers)
        numbers.uniq.sort.map { Marker.new(number: it) }
      end
  end
end
