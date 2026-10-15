class RenameHandbookSourceTypeToFilesystem < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE documents SET source_type = 'filesystem' WHERE source_type = 'handbook'"
  end

  def down
    execute "UPDATE documents SET source_type = 'handbook' WHERE source_type = 'filesystem'"
  end
end
