RubyLLM.configure do |config|
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY") { Rails.application.credentials.dig(:anthropic, :api_key) }
end
