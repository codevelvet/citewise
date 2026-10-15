module Chunking
  # Splits a Markdown document into chunks along its heading structure.
  #
  #   Chunking::MarkdownChunker.new.call(markdown, title: "Engineering")
  #   # => [#<data Chunking::Chunk content=..., heading_path=["Engineering", "Culture"], ...>, ...]
  #
  # Chunk content is the original Markdown source of a section's body. Headings
  # live in heading_path, which always starts with the document title.
  class MarkdownChunker
    PARSE_OPTIONS = { extension: { table: true, front_matter_delimiter: "---" } }.freeze
    # Never split, and never used as overlap.
    ATOMIC_TYPES = %i[code_block table].freeze
    SENTENCE_BOUNDARY = /(?<=[.!?])\s+/

    Section = Data.define(:heading_path, :headings, :blocks)
    # items are the units a block may be split into: list items for a list, else the whole block.
    Block = Data.define(:type, :text, :items)
    Piece = Data.define(:heading_path, :headings, :text)

    def initialize(target_tokens: 400, max_tokens: 512, overlap_tokens: 50, token_counter: TokenCounter::Approximate.new)
      unless 0 < target_tokens && target_tokens <= max_tokens && 0 <= overlap_tokens && overlap_tokens < target_tokens
        raise ArgumentError, "expected 0 < target_tokens <= max_tokens and 0 <= overlap_tokens < target_tokens"
      end

      @target_tokens, @max_tokens, @overlap_tokens = target_tokens, max_tokens, overlap_tokens
      @token_counter = token_counter
    end

    def call(markdown, title:)
      lines = markdown.lines
      document = Commonmarker.parse(markdown, options: PARSE_OPTIONS)
      title = front_matter_title(document, lines) || title

      pieces = sections(document, lines, title).flat_map { |section| split(section) }
      pieces.each_with_index.map { |piece, position| build_chunk(piece, position) }
    end

    private
      attr_reader :target_tokens, :max_tokens, :overlap_tokens, :token_counter

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

        document.each do |node|
          case node.type
          when :frontmatter
            next
          when :heading
            headings.pop while headings.any? && headings.last[:level] >= node.header_level
            headings.push(level: node.header_level, text: plain_text(node), source: source(node, lines))
            sections << Section.new(heading_path: [ title, *headings.pluck(:text) ], headings: headings.pluck(:source), blocks: [])
          else
            text = source(node, lines)
            items = node.type == :list ? node.map { |item| source(item, lines) } : [ text ]
            sections.last.blocks << Block.new(type: node.type, text: text, items: items) if text.present?
          end
        end

        sections.reject { |section| section.blocks.empty? }
      end

      # Sections over max_tokens are packed into pieces of about target_tokens,
      # breaking only between blocks or list items. Each piece after the first
      # starts with the last sentences of the one before it.
      def split(section)
        text = join(section.blocks)
        return [ piece(section, text) ] if count(text) <= max_tokens

        packs = []
        carry, current = [], []
        units(section).each do |unit|
          if current.any? && count(join(carry + current + [ unit ])) > target_tokens
            packs << carry + current
            carry, current = overlap(current.last), []
          end
          carry = [] if current.empty? && count(join(carry + [ unit ])) > max_tokens
          current << unit
        end
        packs << carry + current

        packs.map { |units| piece(section, join(units)) }
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
          break if count([ sentence, *sentences ].join(" ")) > overlap_tokens
          sentences.unshift(sentence)
        end
        return [] if sentences.empty?

        text = sentences.join(" ")
        [ Block.new(type: :paragraph, text: text, items: [ text ]) ]
      end

      def piece(section, text)
        Piece.new(heading_path: section.heading_path, headings: section.headings, text: text)
      end

      def join(blocks)
        blocks.map(&:text).join("\n\n")
      end

      def count(text)
        token_counter.count(text)
      end

      # Lines spanned by a node, taken verbatim from the input so fences, tables,
      # and lists keep their exact Markdown.
      def source(node, lines)
        position = node.source_position
        # A node ending at column 0 actually ends on the previous line.
        last_line = position[:end_column].zero? ? position[:end_line] - 1 : position[:end_line]
        lines[(position[:start_line] - 1)...last_line].join.rstrip
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
          token_count: count(content),
          content_hash: Digest::SHA256.hexdigest(content)
        )
      end
  end
end
