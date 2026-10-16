# A minimal client for Voyage AI's embeddings API. See Voyage::Client.
module Voyage
  class Error < StandardError; end

  # Rate limits, server errors, and timeouts: worth retrying, after retry_after seconds when Voyage says.
  class TransientError < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  # Bad keys, wrong hosts, and invalid requests: retrying won't help.
  class PermanentError < Error; end
end
