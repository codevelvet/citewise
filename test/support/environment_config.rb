# Reads another environment's settings without booting it: evaluates config/environments/<name>.rb
# with Rails.application.configure pointed at a recorder.
#
#   config = EnvironmentConfig.load("production")
#   config.force_ssl                    # => true
#   config.active_storage.service       # => :r2
#
# A setting the file never assigns reads back as another (empty) recorder, never nil.
module EnvironmentConfig
  def self.load(name)
    config = Recorder.new
    application = Object.new
    application.define_singleton_method(:config) { config }
    application.define_singleton_method(:configure) { |&block| instance_eval(&block) }

    rails = Module.new
    rails.define_singleton_method(:application) { application }
    rails.define_singleton_method(:method_missing) { |method, *args, &block| ::Rails.public_send(method, *args, &block) }
    rails.define_singleton_method(:respond_to_missing?) { |method, include_private = false| ::Rails.respond_to?(method, include_private) }

    # String module_eval resolves constants in sandbox first, so the file's Rails is the stand-in.
    sandbox = Module.new
    sandbox.const_set(:Rails, rails)
    path = ::Rails.root.join("config/environments/#{name}.rb")
    sandbox.module_eval(path.read, path.to_s)
    config
  end

  class Recorder
    def initialize
      @values = {}
    end

    def [](key) = @values[key]
    def []=(key, value)
      @values[key] = value
    end

    def method_missing(method, *args)
      if method.end_with?("=") && args.size == 1
        @values[method.to_s.delete_suffix("=").to_sym] = args.first
      elsif args.empty?
        @values.fetch(method) { @values[method] = Recorder.new }
      else
        super
      end
    end

    def respond_to_missing?(*) = true
  end
end
