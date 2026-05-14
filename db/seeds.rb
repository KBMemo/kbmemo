# frozen_string_literal: true

# メモディレクトリのバケット（home / share / public）と各アカウントの u-{id} 領域。
# 詳細は docs/architecture/memo-directory-layout.adoc を参照。
MemoDirectory::UserSpace.ensure_bucket_structure!
Account.find_each { |a| MemoDirectory::UserSpace.ensure_for_account!(a) }
MemoDirectory::UserSpace.reconcile_legacy_flat_directories!
