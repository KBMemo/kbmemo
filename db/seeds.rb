# frozen_string_literal: true

# メモディレクトリのバケット（home / share / public）と各アカウントの u-{id} 領域。
# 詳細は docs/architecture/memo-directory-layout.adoc を参照。
#
# db:schema:load 直後はルート行が無いため、ensure_root! から始める。
MemoDirectory.ensure_root!
MemoDirectory::UserSpace.ensure_bucket_structure!
MemoDirectory::SystemSpace.ensure_buckets!
Account.find_each { |a| MemoDirectory::UserSpace.ensure_for_account!(a) }
MemoDirectory::UserSpace.reconcile_legacy_flat_directories!
