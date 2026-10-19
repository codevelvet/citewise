if defined?(Dotenv) && !ENV["CI"]
  begin
    Dotenv.require_keys("ANTHROPIC_API_KEY", "VOYAGE_API_KEY")
  rescue Dotenv::MissingKeys => e
    puts "WARN: Dotenv Missing keys. #{e.message} Check your environment variables."
    Rails.logger.warn "Dotenv Missing keys. #{e.message} Check your environment variables."
  end
end
