require "test_helper"

class QuestionsHelperTest < ActionView::TestCase
  Text = Question::CitedAnswer::Text
  Marker = Question::CitedAnswer::Marker

  test "a marker links to its card and names the citations of the span it follows" do
    render_paragraph [ Text.new(text: "Leave carries over.", citation_ids: [ 0, 2 ], numbers: [ 1 ]), Marker.new(number: 1, citation_ids: [ 0, 2 ]) ]

    assert_select "a[href='#source-1'][aria-label='Source 1'][aria-controls='source-1']", "1" do |marker|
      assert_equal [ "false", "1", "0 2", "marker", "citations#selectMarker" ],
                   marker.first.attributes.values_at("data-turbo", "data-source-number", "data-citation-ids", "data-citations-target", "data-action").map(&:value)
      assert_no_match(/aria-pressed/, marker.to_html)
    end
  end

  test "a cited span names its citations and source numbers, and uncited text is bare" do
    render_paragraph [ Text.new(text: "Cited.", citation_ids: [ 0, 1 ], numbers: [ 1, 2 ]), Text.new(text: " Uncited.", citation_ids: [], numbers: []) ]

    assert_select "span[data-citation-ids='0 1'][data-source-numbers='1 2']", "Cited."
    assert_select "span", count: 1
    assert_includes rendered, " Uncited."
  end

  test "escapes answer text" do
    render_paragraph [ Text.new(text: "<b>bold</b>", citation_ids: [], numbers: []) ]

    assert_equal "&lt;b&gt;bold&lt;/b&gt;", rendered.to_s
  end

  private
    def render_paragraph(parts)
      render html: cited_paragraph(parts)
    end
end
