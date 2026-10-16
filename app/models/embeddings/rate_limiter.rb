module Embeddings
  # Keeps embedding requests within per-minute request and token budgets by
  # sleeping until a request fits in a sliding one-minute window.
  #
  #   limiter.acquire(estimated_tokens) # returns once the request may be sent
  #
  # The window lives in this process only, so the budgets hold only while one
  # process with one thread does the embedding (see config/queue.yml).
  # Multiple processes will create their own RateLimiter.
  class RateLimiter
    WINDOW = 60.0
    DEFAULT_MUTEX = Mutex.new

    # Shared by every job in the worker process, so the budget spans jobs.
    def self.default
      DEFAULT_MUTEX.synchronize do
        @default ||= new(**Rails.configuration.x.embeddings.slice(:requests_per_minute, :tokens_per_minute))
      end
    end

    def initialize(requests_per_minute:, tokens_per_minute:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
      @requests_per_minute = requests_per_minute
      @tokens_per_minute = tokens_per_minute
      @clock = clock
      @sleeper = sleeper
      @sent = [] # [ time, tokens ] per request, oldest first
      @mutex = Mutex.new
    end

    # Do not call acquire in a database transaction
    # acquire can sleep for WINDOW seconds which hold the db connection for the whole wait
    def acquire(tokens)
      # A request larger than the whole budget could never fit; let it through on an empty window.
      tokens = [ tokens, @tokens_per_minute ].min

      @mutex.synchronize do
        loop do
          now = @clock.call
          @sent.reject! { |time, _| time <= now - WINDOW }
          wait = wait_for(tokens, now)
          break @sent << [ now, tokens ] unless wait.positive?

          @sleeper.call(wait)
        end
      end
    end

    private
      # Seconds until enough earlier requests leave the window for both budgets to hold.
      def wait_for(tokens, now)
        waits = [ 0 ]
        waits << @sent[-@requests_per_minute].first + WINDOW - now if @sent.size >= @requests_per_minute

        excess = @sent.sum(&:last) + tokens - @tokens_per_minute
        if excess.positive?
          freed = 0
          time, _ = @sent.find { |_, sent_tokens| (freed += sent_tokens) >= excess }
          waits << time + WINDOW - now
        end

        waits.max
      end
  end
end
