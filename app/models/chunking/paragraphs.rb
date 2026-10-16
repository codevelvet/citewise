module Chunking
  # Splits chunk content into the passages an answer can cite: paragraphs
  # separated by blank lines.
  #
  #   Chunking::Paragraphs.split("### Carry-over\n\nUp to 5 days carry over.\n\nThe rest lapse.")
  #   # => ["### Carry-over\n\nUp to 5 days carry over.", "The rest lapse."]
  #
  # Fenced code blocks stay whole even when they contain blank lines. Tables
  # need no special case: a blank line always ends a GFM table. A heading that
  # MarkdownChunker kept inline from a merged-in subsection is attached to the
  # paragraph after it, so it is never a passage on its own.
  class Paragraphs
    FENCE = /\A\s*(`{3,}|~{3,})/
    HEADING = /\A {0,3}\#{1,6}(\s|\z)/

    def self.split(content)
      blocks = [ [] ]
      fence = nil

      content.to_s.each_line(chomp: true) do |line|
        if fence
          blocks.last << line
          fence = nil if line.strip.match?(/\A#{Regexp.escape(fence[0])}{#{fence.length},}\z/)
        elsif line.blank?
          blocks << [] if blocks.last.any?
        else
          blocks.last << line
          fence = line[FENCE, 1]
        end
      end

      attach_headings(blocks.map { it.join("\n") }.reject(&:blank?))
    end

    def self.attach_headings(paragraphs)
      headings = []
      passages = paragraphs.each_with_object([]) do |paragraph, passages|
        if paragraph.lines.all? { it.match?(HEADING) }
          headings << paragraph
        else
          passages << [ *headings, paragraph ].join("\n\n")
          headings = []
        end
      end
      headings.any? ? passages << headings.join("\n\n") : passages
    end
    private_class_method :attach_headings
  end
end
