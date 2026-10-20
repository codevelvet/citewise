# Replaces a singleton method for the duration of the block.
module StubHelper
  def stub(object, method, implementation)
    object.define_singleton_method(method, &implementation)
    yield
  ensure
    object.singleton_class.remove_method(method)
  end
end
