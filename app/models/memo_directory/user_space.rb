# frozen_string_literal: true

class MemoDirectory
  # ルート直下の home / share / public と、各アカウントの u-{id} 領域を管理する。
  class UserSpace
    BUCKETS = %w[home share public].freeze
    DEFAULT_TIME_ZONE = "Asia/Tokyo"
    DATE_PATH_SEGMENT = /\A\d{4}-\d{2}-\d{2}\z/

    class << self
      def ensure_bucket_structure!
        root = MemoDirectory.root
        labels = { "home" => "Home", "share" => "Share", "public" => "Public" }
        BUCKETS.each do |seg|
          next if MemoDirectory.exists?(full_path: seg)

          MemoDirectory.create!(parent: root, path_segment: seg, label: labels.fetch(seg))
        end
      end

      def ensure_for_account!(account)
        account = account.is_a?(Account) ? account : Account.find(account)
        ensure_bucket_structure!
        BUCKETS.each do |bucket_seg|
          parent = MemoDirectory.find_by!(full_path: bucket_seg)
          seg = "u-#{account.id}"
          fp = "#{bucket_seg}/#{seg}"
          next if MemoDirectory.exists?(full_path: fp)

          MemoDirectory.create!(
            parent: parent,
            path_segment: seg,
            label: account.display_name.to_s.truncate(80)
          )
        end
      end

      def default_home_directory(account_or_id)
        id = account_or_id.is_a?(Account) ? account_or_id.id : account_or_id
        MemoDirectory.find_by!(full_path: "home/u-#{id}")
      end

      # メモ作成日（created_at）に対応する home/u-{id}/YYYY-MM-DD を返す（冪等）。
      def date_directory(account_or_id, time = Time.current)
        account = account_or_id.is_a?(Account) ? account_or_id : Account.find(account_or_id)
        ensure_for_account!(account)
        segment = date_segment_for(time)
        fp = "home/u-#{account.id}/#{segment}"
        MemoDirectory.find_by(full_path: fp) ||
          MemoDirectory.create!(
            parent: default_home_directory(account),
            path_segment: segment,
            label: segment
          )
      end

      def date_segment_for(time)
        time.in_time_zone(DEFAULT_TIME_ZONE).strftime("%Y-%m-%d")
      end

      # 作成日ベースの再配置対象か（system / docs-sync / 連携用パスは除外）。
      def relocatable_memo?(memo)
        return false unless memo.is_a?(Memo)
        return false if memo.system_space_memo?
        return false if memo.docs_sync_managed?
        return false if memo.memo_directory.nil? || memo.memo_directory.root?

        !reserved_memo_path?(memo.memo_directory.full_path, memo.account_id)
      end

      def reserved_memo_path?(full_path, account_id)
        return true if full_path.start_with?("system/")
        return true if full_path == "home/u-#{account_id}/clippings"
        return true if full_path.start_with?("share/u-#{account_id}/calendar")
        return true if full_path.start_with?("share/u-#{account_id}/dev-docs")

        false
      end

      def share_directory(account_or_id)
        id = account_or_id.is_a?(Account) ? account_or_id.id : account_or_id
        MemoDirectory.find_by!(full_path: "share/u-#{id}")
      end

      def bucket_directory(account_or_id, bucket)
        id = account_or_id.is_a?(Account) ? account_or_id.id : account_or_id
        MemoDirectory.find_by!(full_path: "#{bucket}/u-#{id}")
      end

      # 初回クリップ時に home/u-{id}/clippings を自動作成する。
      def clippings_directory(account)
        account = account.is_a?(Account) ? account : Account.find(account)
        ensure_for_account!(account)

        fp = "home/u-#{account.id}/clippings"
        MemoDirectory.find_by(full_path: fp) ||
          MemoDirectory.create!(
            parent: default_home_directory(account),
            path_segment: "clippings",
            label: "クリップ"
          )
      end

      # `{bucket}/u-{id}` 配下に segments 指定のディレクトリツリーを確保し、末端を返す。
      def ensure_subdirectory!(account, *segments, bucket: KbmemoDocs::SYNC_BUCKET)
        account = account.is_a?(Account) ? account : Account.find(account)
        ensure_for_account!(account)
        parent = bucket_directory(account, bucket)
        segments.flatten.compact_blank.each do |seg|
          fp = "#{parent.full_path}/#{seg}"
          parent = MemoDirectory.find_by(full_path: fp) ||
            MemoDirectory.create!(parent: parent, path_segment: seg, label: seg.tr("-", " ").humanize)
        end
        parent
      end

      # db:seed 用: ルート直下に残った旧フラットディレクトリを先頭ユーザーの home 配下へ移す
      def reconcile_legacy_flat_directories!
        return unless Account.exists?

        root = MemoDirectory.root
        first = Account.order(:id).first
        home_user = MemoDirectory.find_by(full_path: "home/u-#{first.id}")
        return unless home_user

        MemoDirectory.where(parent_id: root.id)
          .where.not(path_segment: BUCKETS + MemoDirectory::PROTECTED_BUCKET_PATHS + [ "" ])
          .find_each do |legacy|
            legacy.update!(parent: home_user)
          end
      end
    end
  end
end
