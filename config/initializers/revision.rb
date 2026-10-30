# Every process (web, worker, shell tasks) logs which commit it runs.
Rails.application.config.after_initialize do
  Rails.logger.info "Citewise revision #{Rails.configuration.x.revision || "unknown"}"
end
