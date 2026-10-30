# Every process (web, worker, shell tasks) logs which commit it runs. Only production sets
# config.x.revision; elsewhere it reads back as empty options, which presence turns into nil.
Rails.application.config.after_initialize do
  Rails.logger.info "Citewise revision #{Rails.configuration.x.revision.presence || "unknown"}"
end
