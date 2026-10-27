class Question
  # Renders a cited passage's Markdown as sanitized HTML for its source card.
  #
  #   Question::PassageRenderer.render("See [the guide](https://example.com/guide) and [the policy](/handbook/leave).")
  #   # => "<p>See <a href=\"https://example.com/guide\" target=\"_blank\" rel=\"noopener noreferrer\">the guide</a> and the policy.</p>"
  #
  # Raw HTML in the source is dropped. Absolute http and https links open in a new tab;
  # any other link becomes its text, since Citewise doesn't host the documents' pages.
  # Images become their alt text. Tables sit in a focusable, horizontally scrolling wrapper.
  class PassageRenderer
    OPTIONS = {
      render: { unsafe: false },
      extension: { table: true, autolink: true, strikethrough: true, header_ids: nil }
    }.freeze
    PLUGINS = { syntax_highlighter: nil }.freeze
    TAGS = %w[p br hr em strong del code pre ul ol li blockquote h1 h2 h3 h4 h5 h6 table thead tbody tr th td a].freeze
    ATTRIBUTES = %w[href target rel].freeze

    def self.render(markdown)
      html = Commonmarker.to_html(markdown.to_s, options: OPTIONS, plugins: PLUGINS)
      fragment = Nokogiri::HTML5.fragment(html)

      fragment.css("img").each { it.replace(fragment.document.create_text_node(it["alt"].to_s)) }
      fragment.css("a").each do |link|
        if external?(link["href"])
          link["target"] = "_blank"
          link["rel"] = "noopener noreferrer"
        else
          link.replace(link.children)
        end
      end

      fragment = Nokogiri::HTML5.fragment(Rails::HTML5::SafeListSanitizer.new.sanitize(fragment.to_html, tags: TAGS, attributes: ATTRIBUTES))
      fragment.css("table").each { it.wrap(%(<div class="passage-table" tabindex="0" role="region" aria-label="Table"></div>)) }
      # Safe: every tag and attribute above passed the allowlist; the wrapper is our own markup.
      fragment.to_html.html_safe
    end

    def self.external?(href)
      uri = URI.parse(href.to_s)
      uri.scheme.in?(%w[http https]) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end
    private_class_method :external?
  end
end
