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

    Section = Data.define(:heading_path, :headings, :blocks)
    Block = Data.define(:type, :text)

    def initialize(token_counter: TokenCounter::Approximate.new)
      @token_counter = token_counter
    end

    def call(markdown, title:)
      lines = markdown.lines
      document = Commonmarker.parse(markdown, options: PARSE_OPTIONS)
      title = front_matter_title(document, lines) || title

      sections(document, lines, title).each_with_index.map do |section, position|
        build_chunk(section.blocks.map(&:text).join("\n\n"), section.heading_path, position)
      end
    end

    private
      attr_reader :token_counter

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
            sections.last.blocks << Block.new(type: node.type, text: text) if text.present?
          end
        end

        sections.reject { |section| section.blocks.empty? }
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

      def build_chunk(content, heading_path, position)
        Chunk.new(
          content: content,
          heading_path: heading_path,
          position: position,
          token_count: token_counter.count(content),
          content_hash: Digest::SHA256.hexdigest(content)
        )
      end
  end
end
