# frozen_string_literal: true

class ChangeMemoDefaultVisibilityToOwnerReadWrite < ActiveRecord::Migration[8.1]
  OWNER_READ_WRITE = 4 # Memo.visibilities[:owner_read_write]
  PUBLIC_EVERYONE = 0

  def change
    change_column_default :memos, :visibility, from: PUBLIC_EVERYONE, to: OWNER_READ_WRITE
  end
end
