# frozen_string_literal: true

# 「自分のみ閲覧」(visibility=2) はオーナー更新ポリシー上「自分のみ読み書き」と実質同じため廃止し、4 に寄せる。
class RemapOwnerReadVisibilityToOwnerReadWrite < ActiveRecord::Migration[8.1]
  OWNER_READ = 2
  OWNER_READ_WRITE = 4

  def up
    execute <<-SQL.squish
      UPDATE memos SET visibility = #{OWNER_READ_WRITE} WHERE visibility = #{OWNER_READ}
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "cannot distinguish memos that were owner_read vs owner_read_write"
  end
end
