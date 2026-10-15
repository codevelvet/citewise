require "test_helper"

class Chunking::TokenCounter::ApproximateTest < ActiveSupport::TestCase
  setup { @counter = Chunking::TokenCounter::Approximate.new }

  test "counts about one token per four characters, rounding up" do
    assert_equal 0, @counter.count("")
    assert_equal 1, @counter.count("abc")
    assert_equal 1, @counter.count("abcd")
    assert_equal 2, @counter.count("abcde")
  end

  test "counts characters, not bytes" do
    assert_equal 1, @counter.count("café")
  end
end
