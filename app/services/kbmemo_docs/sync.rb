# frozen_string_literal: true

module KbmemoDocs
  # docs/**/*.adoc をアカウント配下の dev-docs メモへ upsert する。
  class Sync
    Result = Data.define(:created, :updated, :skipped, :paths, :errors) do
      def self.empty
        new(created: 0, updated: 0, skipped: 0, paths: [], errors: [])
      end

      def summary_lines
        [
          "created=#{created} updated=#{updated} skipped=#{skipped}",
          *paths.map { |line| "  #{line}" },
          *errors.map { |line| "  ERROR #{line}" }
        ]
      end
    end

    DOCS_SYNC_TAG = "docs-sync"

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(
      account: nil,
      docs_root: nil,
      dry_run: false,
      visibility: nil,
      memo_group_id: nil,
      git_commit: false,
      sync_target: nil
    )
      @account = resolve_account(account)
      @docs_root = Pathname.new(docs_root || Rails.root.join("docs"))
      @dry_run = dry_run
      @visibility = resolve_visibility(visibility, memo_group_id)
      @memo_group_id = memo_group_id.presence&.to_i
      @git_commit = git_commit
      @sync_target = (sync_target || KbmemoDocs::SYNC_TARGET).to_s
      unless KbmemoDocs::SYNC_TARGETS.include?(@sync_target)
        raise ArgumentError, "未知の sync_target: #{@sync_target} (#{KbmemoDocs::SYNC_TARGETS.join(', ')})"
      end
      @repo = MemoRepository.new
    end

    def call
      return Result.new(created: 0, updated: 0, skipped: 0, paths: [ "docs root not found: #{@docs_root}" ], errors: []) unless @docs_root.directory?

      result = Result.empty
      index = existing_docs_sync_index

      each_source_file do |relative_path|
        outcome = sync_file(relative_path, index: index)
        result = merge_result(result, outcome)
      rescue StandardError => e
        result = merge_result(result, outcome_line(relative_path, "error: #{e.message}", counters: { errors: 1 }))
      end

      result
    end

    private

    def resolve_account(account)
      if account.is_a?(Account)
        account
      elsif account.present?
        Account.find(account)
      else
        env_id = ENV["KBMEMO_DOCS_SYNC_ACCOUNT_ID"].presence
        return Account.find(env_id) if env_id.present?

        Account.find_by(admin: true) || Account.order(:id).first ||
          raise(ArgumentError, "同期先アカウントがありません")
      end
    end

    def resolve_visibility(visibility, memo_group_id)
      key = (visibility || ENV["KBMEMO_DOCS_SYNC_VISIBILITY"] || "owner_read_write").to_s
      vis = key.to_sym
      unless Memo.visibilities.key?(vis)
        raise ArgumentError, "未知の visibility: #{key}"
      end
      if (vis == :group_read || vis == :group_read_write) && memo_group_id.blank? && ENV["KBMEMO_DOCS_SYNC_MEMO_GROUP_ID"].blank?
        raise ArgumentError, "group_read 系には memo_group_id または KBMEMO_DOCS_SYNC_MEMO_GROUP_ID が必要です"
      end

      vis
    end

    def memo_group_id_for_save
      @memo_group_id || ENV["KBMEMO_DOCS_SYNC_MEMO_GROUP_ID"].presence&.to_i
    end

    def each_source_file
      Dir.glob(@docs_root.join("**", "*.adoc").to_s).sort.each do |abs|
        relative = Pathname.new(abs).relative_path_from(@docs_root).to_s
        yield relative
      end
    end

    def existing_docs_sync_index
      path_sql = MemoPropertiesSql.json_text_at("docs_sync", "source_path")
      Memo.where(account_id: @account.id)
        .where("#{path_sql} IS NOT NULL")
        .index_by { |memo| memo.properties.dig("docs_sync", "source_path") }
    end

    def sync_file(relative_path, index:)
      source = AdocSource.load(relative_path, root: @docs_root)
      memo = index[source.source_path]
      previous_sha = memo&.properties&.dig("docs_sync", "content_sha256")

      if memo && previous_sha == source.content_sha256
        return outcome_line(relative_path, "skipped (unchanged)", counters: { skipped: 1 })
      end

      if @dry_run
        action = memo ? "would update" : "would create"
        return outcome_line(relative_path, "#{action} title=#{source.title.inspect}", counters: { skipped: 1 })
      end

      directory = ensure_memo_directory!(directory_segments_for(source))
      if memo
        update_memo!(memo, source, directory)
        assign_tags!(memo, source)
        git_commit!(memo, source) if @git_commit
        outcome_line(relative_path, "updated memo##{memo.id}", counters: { updated: 1 })
      else
        memo = create_memo!(source, directory)
        index[source.source_path] = memo
        assign_tags!(memo, source)
        git_commit!(memo, source) if @git_commit
        outcome_line(relative_path, "created memo##{memo.id}", counters: { created: 1 })
      end
    end

    def directory_segments_for(source)
      dirname_parts = Pathname.new(source.relative_path).dirname.to_s.split("/").reject { |p| p.blank? || p == "." }
      case @sync_target
      when "system"
        [ KbmemoDocs::SYSTEM_DOCS_SEGMENT, *dirname_parts ]
      when "share"
        [ KbmemoDocs::DEV_DOCS_SEGMENT, *dirname_parts ]
      else
        source.memo_directory_segments
      end
    end

    def ensure_memo_directory!(segments)
      case @sync_target
      when "system"
        MemoDirectory::SystemSpace.ensure_subdirectory!(*segments)
      when "share"
        MemoDirectory::UserSpace.ensure_subdirectory!(@account, *segments, bucket: KbmemoDocs::SYNC_BUCKET)
      end
    end

    def create_memo!(source, directory)
      memo = Memo.new(
        account: @account,
        memo_directory: directory,
        title: source.title,
        title_manual: true,
        slug: source.slug_stem,
        slug_manual: true,
        body: source.body,
        visibility: @visibility,
        memo_group_id: group_visibility? ? memo_group_id_for_save : nil,
        properties: docs_sync_properties(source)
      )
      memo.save!
      memo
    end

    def update_memo!(memo, source, directory)
      attrs = {
        memo_directory: directory,
        title: source.title,
        title_manual: true,
        body: source.body,
        properties: memo.properties.merge("docs_sync" => docs_sync_payload(source))
      }
      memo.update!(attrs)
    end

    def docs_sync_properties(source)
      { "docs_sync" => docs_sync_payload(source) }
    end

    def docs_sync_payload(source)
      {
        "source_path" => source.source_path,
        "content_sha256" => source.content_sha256,
        "read_only" => true,
        "synced_at" => Time.current.iso8601
      }
    end

    def assign_tags!(memo, source)
      labels = [ DOCS_SYNC_TAG, *source.path_tags ].uniq
      memo.assign_tags_from_list(labels.join(", "))
      memo.save!
    end

    def group_visibility?
      @visibility == :group_read || @visibility == :group_read_write
    end

    def git_commit!(memo, source)
      return unless @git_commit

      if Rails.env.production?
        Rails.logger.warn("[kbmemo:docs:sync] git commit skipped in production for memo##{memo.id}")
        return
      end

      @repo.write_and_commit!(memo, message: %(Sync docs "#{source.source_path}"))
      memo.update_column(:file_committed_at, memo.updated_at)
    end

    def outcome_line(relative_path, message, counters:)
      Result.new(
        created: counters[:created] || 0,
        updated: counters[:updated] || 0,
        skipped: counters[:skipped] || 0,
        paths: [ "#{relative_path}: #{message}" ],
        errors: counters[:errors] ? [ "#{relative_path}: #{message}" ] : []
      )
    end

    def merge_result(left, right)
      Result.new(
        created: left.created + right.created,
        updated: left.updated + right.updated,
        skipped: left.skipped + right.skipped,
        paths: left.paths + right.paths,
        errors: left.errors + right.errors
      )
    end
  end
end
