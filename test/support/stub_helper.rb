# Replaces a singleton method for the duration of the block, then puts back exactly what
# was there: a method defined on the singleton itself is restored (with its visibility),
# and a method inherited from a module or superclass is uncovered by removing the stub.
#
# Stubs change the class for the whole process. That's safe while tests run in forked
# processes (parallelize's default); with threads, stubs would race between tests.
module StubHelper
  def stub(object, method, implementation)
    singleton = object.singleton_class
    own = singleton.method_defined?(method, false) || singleton.private_method_defined?(method, false)
    original = singleton.instance_method(method) if own
    visibility = singleton.private_method_defined?(method, false) ? :private : :public

    object.define_singleton_method(method, &implementation)
    yield
  ensure
    if singleton
      if original
        singleton.define_method(method, original)
        singleton.send(visibility, method)
      elsif singleton.method_defined?(method, false) || singleton.private_method_defined?(method, false)
        singleton.remove_method(method)
      end
    end
  end
end
