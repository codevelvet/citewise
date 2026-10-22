module Chunking
  # Splits a Markdown document into chunks along its heading structure.
  #
  #   Chunking::MarkdownChunker.new.call(markdown, title: "Engineering")
  #   # => [#<data Chunking::Chunk content=..., heading_path=["Engineering", "Culture"], ...>, ...]
  #
  # Chunk content is the original Markdown source of a section's body, minus HTML
  # that renders invisibly: comments, and <script> and <style> elements. Headings
  # live in heading_path, which always starts with the document title.
  class MarkdownChunker
    # Bump whenever chunking logic changes, so #fingerprint shows which documents older code chunked.
    VERSION = 3
    PARSE_OPTIONS = { extension: { table: true, front_matter_delimiter: "---" } }.freeze
    # Never split, and never used as overlap.
    ATOMIC_TYPES = %i[code_block table].freeze
    SENTENCE_BOUNDARY = /(?<=[.!?])\s+/
    # Hugo shortcode tags such as {{% note %}}, {{< figure src="x" >}}, and {{% /note %}}.
    SHORTCODE = /\{\{[<%].*?[%>]\}\}/m
    # How tiny pieces merge with a neighbor:
    #   :none           - never
    #   :within_section - only when the larger piece keeps its own path, e.g. a short subsection into its parent
    #   :common_prefix  - whenever the two share a top-level section; the merged chunk takes their common path
    MERGE_POLICIES = %i[none within_section common_prefix].freeze

    Section = Data.define(:heading_path, :headings, :blocks)
    # items are the units a block may be split into: list items for a list, else the whole block.
    Block = Data.define(:type, :text, :items)
    Piece = Data.define(:heading_path, :headings, :text)

    def initialize(target_tokens: 400, max_tokens: 512, min_tokens: 100, overlap_tokens: 50, merge_policy: :within_section,
                   token_counter: TokenCounter::Approximate.new, logger: Rails.logger)
      unless 0 <= min_tokens && min_tokens <= target_tokens && 0 < target_tokens && target_tokens <= max_tokens &&
             0 <= overlap_tokens && overlap_tokens < target_tokens
        raise ArgumentError, "expected 0 <= min_tokens <= target_tokens <= max_tokens, 0 < target_tokens, and 0 <= overlap_tokens < target_tokens"
      end
      raise ArgumentError, "merge_policy must be one of #{MERGE_POLICIES.join(", ")}" unless merge_policy.in?(MERGE_POLICIES)

      @target_tokens, @max_tokens, @min_tokens, @overlap_tokens = target_tokens, max_tokens, min_tokens, overlap_tokens
      @merge_policy = merge_policy
      @token_counter = token_counter
      @logger = logger
    end

    def call(markdown, title:)
      lines = markdown.lines
      document = Commonmarker.parse(markdown, options: PARSE_OPTIONS)
      title = front_matter_title(document, lines) || title

      pieces = sections(document, lines, title).flat_map { |section| split(section) }
      merge(pieces).each_with_index.map { |piece, position| build_chunk(piece, position) }
    end

    # Identifies the code version and settings that produced a set of chunks, e.g. "1:a3f9c2e81b04".
    # Settings are listed in a fixed order so the same settings always give the same digest.
    def fingerprint
      settings = {
        target_tokens: target_tokens, max_tokens: max_tokens, min_tokens: min_tokens, overlap_tokens: overlap_tokens,
        merge_policy: merge_policy, token_counter: token_counter.class.name
      }
      "#{self.class::VERSION}:#{Digest::SHA256.hexdigest(settings.to_json).first(12)}"
    end

    private
      attr_reader :target_tokens, :max_tokens, :min_tokens, :overlap_tokens, :merge_policy, :token_counter, :logger

      def front_matter_title(document, lines)
        node = document.first_child
        return unless node&.type == :frontmatter

        data = YAML.safe_load(source(node, lines).lines[1...-1].join, permitted_classes: [ Date, Time ])
        data["title"].to_s.strip.presence if data.is_a?(Hash)
      rescue Psych::Exception
        nil
      end

      def sections(document, lines, title)
        headings = []
        sections = [ Section.new(heading_path: [ title ], headings: [], blocks: []) ]
        skipped_diagrams = 0
        removed = { comments: 0, elements: 0 }

        document.each do |node|
          case node.type
          when :frontmatter, :thematic_break
            next
          when :heading
            headings.pop while headings.any? && headings.last[:level] >= node.header_level
            headings.push(level: node.header_level, text: plain_text(node), source: source(node, lines, hidden_spans(node, lines, removed)))
            sections << Section.new(heading_path: [ title, *headings.pluck(:text) ], headings: headings.pluck(:source), blocks: [])
          else
            # Diagram source is mostly syntax: it retrieves poorly and adds keyword-search noise.
            if node.type == :code_block && node.fence_info.split.first == "mermaid"
              skipped_diagrams += 1
            elsif (block = block(node, lines, removed))
              sections.last.blocks << block
            end
          end
        end

        logger.info("Skipped #{skipped_diagrams} mermaid code block(s) in #{title.inspect}") if skipped_diagrams.positive?
        if removed.values.any?(&:positive?)
          logger.info("Removed #{removed[:comments]} HTML comment(s) and #{removed[:elements]} script or style element(s) in #{title.inspect}")
        end
        sections.reject { |section| section.blocks.empty? }
      end

      # nil for a block with no real content, such as an HTML wrapper <div> or a lone shortcode.
      def block(node, lines, removed)
        hidden = hidden_spans(node, lines, removed)
        text = clean(node, source(node, lines, hidden))
        text = visible_html(text, removed) if node.type == :html_block
        return if text.blank?

        items = node.type == :list ? node.map { |item| clean(item, source(item, lines, hidden)) }.compact_blank : [ text ]
        Block.new(type: node.type, text: text, items: items)
      end

      # An HTML block without its comments, <script>, and <style>, or nil when no text
      # remains (entities such as &nbsp; are decoded first). The block is re-serialized
      # only when something was removed, which normalizes its markup. An unterminated
      # comment hides the rest of the block, as it does in a browser.
      def visible_html(html, removed)
        fragment = Nokogiri::HTML5.fragment(html)
        hidden = fragment.xpath(".//comment() | .//script | .//style").each(&:remove)
        removed[:comments] += hidden.count(&:comment?)
        removed[:elements] += hidden.count(&:element?)
        return if fragment.text.blank?

        hidden.empty? ? html : fragment.to_html.strip
      end

      # [first, last] source positions of inline HTML that renders invisibly: comments
      # (including markup a browser treats as one, like <?php ?>), and <script> or
      # <style> elements with their contents. Code spans and code blocks never contain
      # html_inline nodes, so they keep their source as written.
      def hidden_spans(node, lines, removed)
        spans = []
        node.walk do |container|
          next unless container.type.in?(%i[paragraph heading table_cell])

          opened = nil
          container.walk do |inline|
            next unless inline.type == :html_inline

            html = between(lines, start_of(inline), end_of(inline))
            if opened
              next unless html.downcase.start_with?("</#{opened[:name]}")
              spans << [ opened[:start], end_of(inline) ]
              opened = nil
            elsif (tag = Nokogiri::HTML5.fragment(html).children.first)&.comment?
              spans << [ start_of(inline), end_of(inline) ]
              removed[:comments] += 1
            elsif tag&.name.in?(%w[script style])
              opened = { name: tag.name, start: start_of(inline) }
              removed[:elements] += 1
            end
          end
          # A browser hides everything after an unclosed <script> or <style>; stop at the end of the paragraph.
          spans << [ opened[:start], end_of(container) ] if opened
        end
        spans
      end

      # Removes Hugo shortcode tags, keeping any text they wrap.
      def clean(node, text)
        return text if node.type == :code_block || !text.match?(SHORTCODE)

        text.gsub(SHORTCODE, "").gsub(/^[ \t]+$/, "").gsub(/\n{3,}/, "\n\n").strip
      end

      # Sections over max_tokens are packed into pieces of about target_tokens,
      # breaking only between blocks or list items. Each piece after the first
      # starts with the last sentences of the one before it.
      def split(section)
        text = join(section.blocks)
        return [ piece(section, text) ] if tokens(text) <= max_tokens

        packs = []
        carry, current = [], []
        units(section).each do |unit|
          if current.any? && tokens(join(carry + current + [ unit ])) > target_tokens
            packs << [ carry, current ]
            carry, current = overlap(current.last), []
          end
          carry = [] if current.empty? && tokens(join(carry + [ unit ])) > max_tokens
          current << unit
        end
        packs << [ carry, current ]

        # Fold a tiny last pack back into the one before, without its overlap.
        if packs.size > 1 && tokens(join(current)) < min_tokens
          (previous_carry, previous), _last = packs.last(2)
          packs[-2..] = [ [ previous_carry, previous + current ] ] if tokens(join(previous_carry + previous + current)) <= max_tokens
        end

        packs.map { |carry, units| piece(section, join(carry + units)) }
      end

      def units(section)
        section.blocks.flat_map do |block|
          block.items.map { |item| Block.new(type: block.type, text: item, items: [ item ]) }
        end
      end

      def overlap(unit)
        return [] if overlap_tokens.zero? || unit.type.in?(ATOMIC_TYPES)

        sentences = []
        unit.text.split(SENTENCE_BOUNDARY).reverse_each do |sentence|
          break if tokens([ sentence, *sentences ].join(" ")) > overlap_tokens
          sentences.unshift(sentence)
        end
        return [] if sentences.empty?

        text = sentences.join(" ")
        [ Block.new(type: :paragraph, text: text, items: [ text ]) ]
      end

      # A piece under min_tokens joins its previous neighbor, or else its next one,
      # when the result fits in max_tokens, the two share a top-level section, and
      # merge_policy allows it. Otherwise it stays small: a precise heading path
      # retrieves better than a vague one.
      def merge(pieces)
        return pieces if merge_policy == :none

        pieces.each_with_object([]) do |piece, merged|
          previous = merged.last
          combined = combine(previous, piece) if previous && (tiny?(previous) || tiny?(piece))

          if combined && mergeable?(previous, piece, combined)
            merged[-1] = combined
          else
            merged << piece
          end
        end
      end

      def mergeable?(first, second, combined)
        return false unless combined.heading_path.size >= 2 && tokens(combined.text) <= max_tokens

        # :within_section keeps the majority of the text labeled as precisely as before.
        merge_policy == :common_prefix || combined.heading_path == [ first, second ].max_by { |piece| tokens(piece.text) }.heading_path
      end

      # The combined piece sits at the common heading path; headings below it
      # move into the content so the merged-in subsections stay labeled.
      def combine(first, second)
        path = first.heading_path.zip(second.heading_path).take_while { |a, b| a == b }.map(&:first)
        depth = path.size - 1
        text = [ first, second ].map { |piece| [ *piece.headings.drop(depth), piece.text ].join("\n\n") }.join("\n\n")
        Piece.new(heading_path: path, headings: first.headings.first(depth), text: text)
      end

      def tiny?(piece)
        tokens(piece.text) < min_tokens
      end

      def piece(section, text)
        Piece.new(heading_path: section.heading_path, headings: section.headings, text: text)
      end

      def join(blocks)
        blocks.map(&:text).join("\n\n")
      end

      def tokens(text)
        token_counter.count(text)
      end

      # Lines spanned by a node, taken verbatim from the input so fences, tables,
      # and lists keep their exact Markdown, minus the hidden spans inside them.
      def source(node, lines, hidden = [])
        position = node.source_position
        # A node ending at column 0 actually ends on the previous line.
        last_line = position[:end_column].zero? ? position[:end_line] - 1 : position[:end_line]
        text = lines[(position[:start_line] - 1)...last_line].join
        # Spans are in document order; cutting from the end keeps earlier offsets valid.
        hidden.reverse_each do |first, last|
          next unless first.first >= position[:start_line] && last.first <= last_line
          text.bytesplice(offset(lines, position[:start_line], first)..offset(lines, position[:start_line], last), "")
        end
        text.rstrip
      end

      # Source text from position first through position last, inclusive.
      def between(lines, first, last)
        lines[(first.first - 1)...last.first].join.byteslice(offset(lines, first.first, first)..offset(lines, first.first, last))
      end

      # Byte offset of a [line, column] position in the text that starts at start_line.
      # Commonmarker counts columns in bytes, from 1.
      def offset(lines, start_line, (line, column))
        lines[(start_line - 1)...(line - 1)].sum(&:bytesize) + column - 1
      end

      def start_of(node)
        node.source_position.values_at(:start_line, :start_column)
      end

      def end_of(node)
        node.source_position.values_at(:end_line, :end_column)
      end

      def plain_text(node)
        text = +""
        node.walk { |child| text << child.string_content if child.type.in?(%i[text code]) }
        text.strip
      end

      def build_chunk(piece, position)
        content = piece.text
        Chunk.new(
          content: content,
          heading_path: piece.heading_path,
          position: position,
          token_count: tokens(content),
          content_hash: Digest::SHA256.hexdigest(content)
        )
      end
  end
end
