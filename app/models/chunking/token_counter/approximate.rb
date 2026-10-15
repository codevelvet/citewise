module Chunking
  module TokenCounter
    # Estimates tokens at ~4 characters each. Any object responding to
    # #count(text) -> Integer can stand in for a real tokenizer.
    class Approximate
      CHARACTERS_PER_TOKEN = 4.0

      def count(text)
        (text.length / CHARACTERS_PER_TOKEN).ceil
      end
    end
  end
end
