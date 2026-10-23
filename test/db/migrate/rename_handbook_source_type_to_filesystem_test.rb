require "test_helper"
require Rails.root.join("db/migrate/20261015170000_rename_handbook_source_type_to_filesystem")

class RenameHandbookSourceTypeToFilesystemTest < ActiveSupport::TestCase
  include TestData

  test "converts handbook rows to filesystem and leaves others alone" do
    connection = ActiveRecord::Base.connection
    connection.execute("INSERT INTO documents (title, source_type, created_at, updated_at) VALUES ('Old', 'handbook', now(), now())")
    old = Document.find_by!(title: "Old")

    ActiveRecord::Migration.suppress_messages { RenameHandbookSourceTypeToFilesystem.new.migrate(:up) }

    assert_equal "filesystem", old.reload.source_type
    assert_equal "upload", documents(:pending_upload).reload.source_type
  end
end
