# frozen_string_literal: true

module Api
  module V1
    class MemoWriter
      class StaleMemo < StandardError
        attr_reader :memo

        def initialize(memo)
          @memo = memo
          super("stale memo")
        end
      end

      def initialize(account:)
        @account = account
      end

      def create!(attributes)
        memo = Memo.new(account: @account)
        apply_attributes!(memo, attributes)
        memo.apply_title_from_body_rules!
        memo.apply_slug_from_title_rules!
        memo.apply_storage_slug!
        memo.save!
        commit!(memo) if attributes.fetch(:commit, true)
        memo
      end

      def update!(memo, attributes:, expected_updated_at:, replace: false)
        check_stale!(memo, expected_updated_at)

        if replace
          memo.title = attributes.fetch(:title)
          memo.body = attributes.fetch(:body)
        else
          apply_patch!(memo, attributes)
        end

        apply_tags!(memo, attributes[:tags]) if attributes.key?(:tags)
        apply_visibility!(memo, attributes[:visibility]) if attributes.key?(:visibility)
        apply_properties!(memo, attributes[:properties]) if attributes.key?(:properties)

        memo.apply_title_from_body_rules!
        memo.apply_slug_from_title_rules!
        memo.apply_storage_slug!

        unless memo.valid?
          raise ActiveRecord::RecordInvalid, memo
        end

        if attributes.fetch(:commit, memo.file_committed_at.present?)
          commit!(memo)
        else
          memo.save!
        end

        memo
      end

      def commit!(memo)
        repo = MemoRepository.new
        old_rel = repo.relative_path_for(memo)
        old_abs = repo.absolute_path_for(memo)
        old_assets_rel = repo.assets_dir_relative_for(memo)
        new_rel = repo.relative_path_for(memo)
        new_assets_rel = repo.assets_dir_relative_for(memo)

        if old_abs.exist? && old_rel.to_s != new_rel.to_s
          repo.relocate_path!(from_relative: old_rel, to_relative: new_rel)
        end
        if old_assets_rel.to_s != new_assets_rel.to_s && repo.root.join(old_assets_rel).directory?
          repo.relocate_path!(from_relative: old_assets_rel, to_relative: new_assets_rel)
        end

        repo.write_and_commit!(memo)
        memo.save!
        memo.update_column(:file_committed_at, memo.updated_at)
        memo
      end

      private

      def apply_attributes!(memo, attributes)
        memo.body = attributes.fetch(:body)
        memo.title = attributes[:title] if attributes.key?(:title)
        apply_tags!(memo, attributes[:tags]) if attributes.key?(:tags)
        apply_visibility!(memo, attributes[:visibility]) if attributes.key?(:visibility)
        apply_properties!(memo, attributes[:properties]) if attributes.key?(:properties)
      end

      def apply_patch!(memo, attributes)
        memo.title = attributes[:title] if attributes.key?(:title)

        if attributes.key?(:body) && attributes.key?(:append_body)
          raise ArgumentError, "body と append_body は同時に指定できません。"
        end

        if attributes.key?(:body)
          memo.body = attributes[:body]
        elsif attributes.key?(:append_body)
          memo.body = [ memo.body.presence, attributes[:append_body] ].compact.join("\n\n")
        end

        MemoChecklist.sync_properties_from_body!(memo) if attributes.key?(:body) || attributes.key?(:append_body)
      end

      def apply_tags!(memo, tags)
        memo.assign_tags_from_list(Array(tags).join(", "))
      end

      def apply_visibility!(memo, visibility)
        memo.visibility = visibility
      end

      def apply_properties!(memo, properties)
        return unless properties.is_a?(Hash)

        memo.properties = memo.properties.merge(properties)
      end

      def check_stale!(memo, expected_updated_at)
        return if expected_updated_at.blank?

        server_time = memo.updated_at.utc.change(usec: 0)
        client_time = expected_updated_at.utc.change(usec: 0)
        return if server_time == client_time

        raise StaleMemo, memo
      end
    end
  end
end
