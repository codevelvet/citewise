require "test_helper"

class AskJobTest < ActiveJob::TestCase
  include FakeAnswerer::TestHelper

  setup do
    @question = Question.create!(text: "How much paid leave do I get?")
    embedder = FakeEmbedder.new
    ChunkEmbedding.create!(chunk: chunks(:leave), model: "voyage-4-lite", strategy: :raw, dimensions: 1024,
                           embedding: embedder.vector_for("leave"), input_hash: "abc")
  end

  test "answers the pending question" do
    answerer = FakeAnswerer.new
    with_fake_embedder { with_fake_answerer(answerer) { AskJob.perform_now(@question) } }

    assert @question.reload.answered?
    assert_equal [ [ @question.text, [ chunks(:leave) ] ] ], answerer.calls
  end

  test "runs on the default queue" do
    assert_equal "default", AskJob.new(@question).queue_name
  end

  test "skips a question that isn't pending" do
    # The abandoned sweep failed it while the job waited behind other asks.
    @question.update!(created_at: 2.hours.ago)
    Question.fail_abandoned
    answerer = FakeAnswerer.new

    with_fake_embedder { with_fake_answerer(answerer) { AskJob.perform_now(@question.reload) } }

    assert_empty answerer.calls
    assert @question.reload.failed?
  end

  test "retries a transient embedding error after Retry-After, leaving the question pending" do
    embedder = FakeEmbedder.new
    embedder.error = Embeddings::Embedder::TransientError.new("Embedding provider 429: Rate limit exceeded", retry_after: 7)
    answerer = FakeAnswerer.new

    freeze_time do
      with_fake_embedder(embedder) do
        with_fake_answerer(answerer) do
          assert_enqueued_with(job: AskJob, args: [ @question ], at: 7.seconds.from_now) { AskJob.perform_now(@question) }
        end
      end
    end
    assert @question.reload.pending?
    assert_nil @question.error
    assert_empty answerer.calls
  end

  test "retries a transient embedding error without Retry-After with polynomial backoff and jitter" do
    embedder = FakeEmbedder.new
    embedder.error = Embeddings::Embedder::TransientError.new("Embedding provider 503: Service unavailable")

    freeze_time do
      with_fake_embedder(embedder) { with_fake_answerer { AskJob.perform_now(@question) } }

      wait = enqueued_jobs.sole[:at] - Time.current.to_f
      assert_in_delta 3 * 1.075, wait, 3 * 0.075 # first execution: 1**4 + 2 seconds, plus up to 15%
    end
    assert @question.reload.pending?
  end

  test "the last attempt at a transient embedding error fails the question" do
    embedder = FakeEmbedder.new
    embedder.error = Embeddings::Embedder::TransientError.new("Embedding provider 429: Rate limit exceeded", retry_after: 7)
    job = AskJob.new(@question)
    job.executions = AskJob::ATTEMPTS - 1

    with_fake_embedder(embedder) do
      with_fake_answerer { assert_raises(Embeddings::Embedder::TransientError) { job.perform_now } }
    end
    assert_no_enqueued_jobs
    assert @question.reload.failed?
    assert_equal "Embedding provider 429: Rate limit exceeded", @question.error
  end

  test "any other error fails the question without a retry" do
    [ Answering::Answerer::TransientError.new("Answering provider 529: Overloaded"),
      Embeddings::Embedder::PermanentError.new("Embedding provider 401: Bad key") ].each do |failure|
      question = Question.create!(text: "How much paid leave do I get?")
      embedder, answerer = FakeEmbedder.new, FakeAnswerer.new
      (failure.is_a?(Embeddings::Embedder::Error) ? embedder : answerer).error = failure

      with_fake_embedder(embedder) do
        with_fake_answerer(answerer) { assert_raises(failure.class) { AskJob.perform_now(question) } }
      end
      assert_no_enqueued_jobs
      assert question.reload.failed?
      assert_equal failure.message, question.error
    end
  end

  test "runs one ask at a time by default, holding the rest" do
    first, second, third = 3.times.map { AskJob.new(Question.create!(text: "Question #{it}?")) }

    [ first, second, third ].each { |job| SolidQueue::Job.enqueue(job) }

    assert_equal [ first.job_id ], SolidQueue::ReadyExecution.includes(:job).map { it.job.active_job_id }
    assert_equal [ second.job_id, third.job_id ].sort, SolidQueue::BlockedExecution.includes(:job).map { it.job.active_job_id }.sort
  end

  test "the lock covers queue wait plus AskService's worst case" do
    freeze_time do
      job = AskJob.new(@question)
      SolidQueue::Job.enqueue(job)

      semaphore = SolidQueue::Semaphore.find_by!(key: job.concurrency_key)
      assert_equal "ask/ask", semaphore.key
      assert_equal AskJob::LOCK_DURATION.from_now, semaphore.expires_at
    end
    assert_operator AskJob::LOCK_DURATION, :>, 33.minutes
  end
end
