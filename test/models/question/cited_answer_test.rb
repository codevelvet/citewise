require "test_helper"

class Question::CitedAnswerTest < ActiveSupport::TestCase
  include TestData

  Text = Question::CitedAnswer::Text
  Marker = Question::CitedAnswer::Marker

  LEAVE = "Employee Handbook > Benefits > Paid leave"
  CARRY = "Leave Policy > Benefits"

  test "places a marker after a cited span, before its trailing whitespace" do
    answer = "You get 20 days. Ask HR for more."
    cited = Question::CitedAnswer.new(answer, [ citation(1, answer, "You get 20 days. ") ])

    assert_equal [ [ Text.new(text: "You get 20 days.", citation_ids: [ 0 ], numbers: [ 1 ]), Marker.new(number: 1),
                     Text.new(text: " Ask HR for more.", citation_ids: [], numbers: []) ] ], cited.paragraphs
  end

  test "a span cited by several chunks shows each distinct number once, in order" do
    answer = "Leave accrues monthly and carries over."
    citations = [ citation(2, answer, answer, cited_text: "Up to 5 days carry over."), citation(1, answer, answer),
                  citation(2, answer, answer, cited_text: "Paid leave accrues monthly.") ]

    cited = Question::CitedAnswer.new(answer, citations)

    assert_equal [ [ Text.new(text: answer, citation_ids: [ 0, 1, 2 ], numbers: [ 1, 2 ]), Marker.new(number: 1), Marker.new(number: 2) ] ], cited.paragraphs
    assert_equal [ 1, 2 ], cited.sources.map(&:number)
  end

  test "numbers chunks by first use in the answer, not by citation order" do
    answer = "First claim. Second claim."
    cited = Question::CitedAnswer.new(answer, [ citation(7, answer, "Second claim."), citation(3, answer, "First claim. ") ])

    assert_equal [ 1, 2 ], cited.paragraphs.first.grep(Marker).map(&:number)
    assert_equal [ [ 1, 3 ], [ 2, 7 ] ], cited.sources.map { [ it.number, chunk_of(it) ] }
  end

  test "two citations from one chunk share its number, and its source lists both passages" do
    answer = "Leave accrues monthly. Five days carry over."
    citations = [ citation(2, answer, "Leave accrues monthly. ", cited_text: "Paid leave accrues monthly."),
                  citation(2, answer, "Five days carry over.", cited_text: "### Carry-over\n\nUp to 5 days carry over.") ]

    cited = Question::CitedAnswer.new(answer, citations)

    assert_equal [ 1, 1 ], cited.paragraphs.first.grep(Marker).map(&:number)
    source = cited.sources.sole
    assert_equal [ 1, "Leave Policy", CARRY ], [ source.number, source.document_title, source.source_title ]
    assert_equal [ [ [ 0 ], "Paid leave accrues monthly." ], [ [ 1 ], "### Carry-over\n\nUp to 5 days carry over." ] ],
                 source.passages.map { [ it.citation_ids, it.text ] }
  end

  test "the same passage cited twice is listed once, naming both citations" do
    answer = "One. Two."
    cited = Question::CitedAnswer.new(answer, [ citation(1, answer, "One. "), citation(1, answer, "Two.") ])

    assert_equal [ [ 0, 1 ] ], cited.sources.sole.passages.map(&:citation_ids)
  end

  test "an answer without citations is plain paragraphs with no sources" do
    cited = Question::CitedAnswer.new("The documents don't cover that.\n\nAsk HR.", [])

    assert_not cited.cited?
    assert_equal [ [ Text.new(text: "The documents don't cover that.", citation_ids: [], numbers: []) ],
                   [ Text.new(text: "Ask HR.", citation_ids: [], numbers: []) ] ], cited.paragraphs
    assert_empty cited.sources
  end

  test "an answer with no sources is the fixed answer, unmarked" do
    cited = Question::CitedAnswer.new(Answering::AskService::NO_SOURCES_ANSWER, [])

    assert_equal [ [ Text.new(text: Answering::AskService::NO_SOURCES_ANSWER, citation_ids: [], numbers: []) ] ], cited.paragraphs
    assert_empty cited.sources
  end

  test "no answer yet has no paragraphs" do
    assert_empty Question::CitedAnswer.new(nil, []).paragraphs
  end

  test "keeps paragraph breaks, and splits a span that crosses one, with the marker after its last sentence" do
    answer = "Intro line.\n\nCited start.\n\nCited end.\n\nUncited."
    cited = Question::CitedAnswer.new(answer, [ citation(1, answer, "Cited start.\n\nCited end.\n\n") ])

    assert_equal [
      [ Text.new(text: "Intro line.", citation_ids: [], numbers: []) ],
      [ Text.new(text: "Cited start.", citation_ids: [ 0 ], numbers: [ 1 ]) ],
      [ Text.new(text: "Cited end.", citation_ids: [ 0 ], numbers: [ 1 ]), Marker.new(number: 1) ],
      [ Text.new(text: "Uncited.", citation_ids: [], numbers: []) ]
    ], cited.paragraphs
  end

  test "keeps single line breaks inside a paragraph" do
    cited = Question::CitedAnswer.new("Steps:\n- one\n- two", [])

    assert_equal "Steps:\n- one\n- two", cited.paragraphs.sole.sole.text
  end

  test "overlapping spans split into segments naming each citation that covers them" do
    answer = "Alpha beta gamma."
    citations = [ citation(1, answer, "Alpha beta "), citation(2, answer, "beta gamma.") ]

    assert_equal [
      Text.new(text: "Alpha ", citation_ids: [ 0 ], numbers: [ 1 ]),
      Text.new(text: "beta", citation_ids: [ 0, 1 ], numbers: [ 1, 2 ]), Marker.new(number: 1),
      Text.new(text: " gamma.", citation_ids: [ 1 ], numbers: [ 2 ]), Marker.new(number: 2)
    ], Question::CitedAnswer.new(answer, citations).paragraphs.sole
  end

  test "offsets count characters, not bytes" do
    answer = "Café hours are 9–5. Then close."
    cited = Question::CitedAnswer.new(answer, [ citation(1, answer, "Café hours are 9–5. ") ])

    assert_equal "Café hours are 9–5.", cited.paragraphs.sole.first.text
  end

  test "keeps markup as plain text for the view to escape" do
    answer = "<script>alert(1)</script> is not run."
    cited = Question::CitedAnswer.new(answer, [ citation(1, answer, answer, cited_text: "<b>bold</b>") ])

    assert_equal answer, cited.paragraphs.sole.first.text
    assert_equal "<b>bold</b>", cited.sources.sole.passages.sole.text
  end

  test "Question#cited_answer uses the stored answer and citations" do
    answer = "Full-time employees accrue 20 days of paid leave per year."
    question = Question.new(text: "Leave?", answer: answer, citations: [ citation(chunks(:leave).id, answer, answer) ])

    assert_equal [ LEAVE ], question.cited_answer.sources.map(&:source_title)
  end

  private
    def citation(chunk_id, answer, span, cited_text: "Passage of chunk #{chunk_id}.")
      start = answer.index(span) or raise "#{span.inspect} isn't in the answer"
      title, path = chunk_id == 2 ? [ "Leave Policy", CARRY ] : [ "Employee Handbook", LEAVE ]
      { "chunk_id" => chunk_id, "cited_text" => cited_text, "answer_start" => start, "answer_end" => start + span.length,
        "document_title" => title, "source_title" => path }
    end

    def chunk_of(source)
      { "Passage of chunk 3." => 3, "Passage of chunk 7." => 7 }.fetch(source.passages.first.text)
    end
end
