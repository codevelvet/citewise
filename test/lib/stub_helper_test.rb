require "test_helper"

class StubHelperTest < ActiveSupport::TestCase
  include StubHelper

  test "restores a method defined directly on the object" do
    klass = Class.new { def self.greet = "hi" }

    stub(klass, :greet, -> { "stubbed" }) { assert_equal "stubbed", klass.greet }

    assert klass.respond_to?(:greet), "greet was deleted instead of restored"
    assert_equal "hi", klass.greet
  end

  test "restores a private singleton method as private" do
    klass = Class.new { class << self; private def secret = "hi"; end }

    stub(klass, :secret, -> { "stubbed" }) { }

    assert klass.singleton_class.private_method_defined?(:secret, false), "secret was deleted instead of restored"
    assert_equal "hi", klass.send(:secret)
    assert_not klass.respond_to?(:secret)
  end

  test "uncovers a method inherited from a module" do
    klass = Class.new { extend(Module.new { def greet = "hi" }) }

    stub(klass, :greet, -> { "stubbed" }) { assert_equal "stubbed", klass.greet }

    assert_equal "hi", klass.greet
    assert_not klass.singleton_class.method_defined?(:greet, false)
  end

  test "restores the original when the block raises" do
    klass = Class.new { def self.greet = "hi" }

    assert_raises(RuntimeError) { stub(klass, :greet, -> { "stubbed" }) { raise "boom" } }

    assert klass.respond_to?(:greet), "greet was deleted instead of restored"
    assert_equal "hi", klass.greet
  end
end
