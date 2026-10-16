require "test_helper"

class Embeddings::RateLimiterTest < ActiveSupport::TestCase
  setup do
    @now = 0.0
    @sleeps = []
    @limiter = Embeddings::RateLimiter.new(requests_per_minute: 3, tokens_per_minute: 10_000,
      clock: -> { @now }, sleeper: ->(seconds) { @sleeps << seconds; @now += seconds })
  end

  test "does not wait while both budgets hold" do
    3.times { @limiter.acquire(3_000) }
    assert_empty @sleeps
  end

  test "waits for the oldest request to leave the window when the request budget is spent" do
    @limiter.acquire(10)
    @now = 5.0
    @limiter.acquire(10)
    @limiter.acquire(10)

    @limiter.acquire(10)
    assert_equal [ 55.0 ], @sleeps
  end

  test "waits until enough tokens leave the window when the token budget is spent" do
    @limiter.acquire(6_000)
    @now = 20.0
    @limiter.acquire(3_000)

    @limiter.acquire(2_000)
    assert_equal [ 40.0 ], @sleeps
  end

  test "lets a request larger than the token budget through on an empty window" do
    @limiter.acquire(25_000)
    assert_empty @sleeps

    @limiter.acquire(1)
    assert_equal [ 60.0 ], @sleeps
  end

  test "reads its budgets from app configuration" do
    limiter = Embeddings::RateLimiter.default
    assert_equal [ 3, 10_000 ], [ limiter.instance_variable_get(:@requests_per_minute), limiter.instance_variable_get(:@tokens_per_minute) ]
  end
end
