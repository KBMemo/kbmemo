# frozen_string_literal: true

class MemoDirectory
  # ルート直下の home / share / public と、各アカウントの u-{id} 領域を管理する。
  class UserSpace
    BUCKETS = %w[home share public].freeze

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
            label: account.email.to_s.truncate(80)
          )
        end
      end

      def default_home_directory(account_or_id)
        id = account_or_id.is_a?(Account) ? account_or_id.id : account_or_id
        MemoDirectory.find_by!(full_path: "home/u-#{id}")
      end

      # db:seed 用: ルート直下に残った旧フラットディレクトリを先頭ユーザーの home 配下へ移す
      def reconcile_legacy_flat_directories!
        return unless Account.exists?

        root = MemoDirectory.root
        first = Account.order(:id).first
        home_user = MemoDirectory.find_by(full_path: "home/u-#{first.id}")
        return unless home_user

        MemoDirectory.where(parent_id: root.id)
          .where.not(path_segment: BUCKETS + [ "" ])
          .find_each do |legacy|
            legacy.update!(parent: home_user)
          end
      end
    end
  end
end
