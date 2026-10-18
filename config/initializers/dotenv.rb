if defined?(Dotenv) && !ENV['CI']
  Dotenv.require_keys("ANTHROPIC_API_KEY", "VOYAGE_API_KEY")
end
