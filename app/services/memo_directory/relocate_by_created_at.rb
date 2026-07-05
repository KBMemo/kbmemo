# frozen_string_literal: true

class MemoDirectory
  # 既存メモを created_at の日付ディレクトリへ再配置し、空の旧フォルダを削除する。
  class RelocateByCreatedAt
    Result = Struct.new(:moved, :skipped, :git_errors, :deleted_directories, :errors, keyword_init: true)

    def self.call(dry_run: true, git_relocate: true, repo: nil)
      new(dry_run: dry_run, git_relocate: git_relocate, repo: repo).call
    end

    def initialize(dry_run: true, git_relocate: true, repo: nil)
      @dry_run = dry_run
      @git_relocate = git_relocate
      @repo = repo || MemoRepository.new
    end

    def call
      result = Result.new(moved: 0, skipped: 0, git_errors: [], deleted_directories: 0, errors: [])

      Account.find_each { |account| UserSpace.ensure_for_account!(account) }

      Memo.includes(:memo_directory, :account).find_each do |memo|
        relocate_memo!(memo, result)
      rescue StandardError => e
        result.errors << "memo##{memo.id}: #{e.message}"
      end

      cleanup_empty_legacy_directories!(result) unless @dry_run

      result
    end

    def summary_lines(result)
      mode = @dry_run ? "dry-run" : "apply"
      lines = [
        "[kbmemo:memos:relocate_by_created_at] #{mode}",
        "  moved: #{result.moved}",
        "  skipped: #{result.skipped}",
        "  deleted_directories: #{result.deleted_directories}"
      ]
      result.git_errors.each { |msg| lines << "  git: #{msg}" }
      result.errors.each { |msg| lines << "  error: #{msg}" }
      lines
    end

    private

    def relocate_memo!(memo, result)
      unless UserSpace.relocatable_memo?(memo)
        result.skipped += 1
        return
      end

      target = UserSpace.date_directory(memo.account_id, memo.created_at)
      if memo.memo_directory_id == target.id
        result.skipped += 1
        return
      end

      if @dry_run
        result.moved += 1
        return
      end

      old_rel = @repo.relative_path_for(memo)
      old_abs = @repo.absolute_path_for(memo)

      memo.memo_directory = target
      memo.apply_storage_slug!
      new_rel = @repo.relative_path_for(memo)

      if @git_relocate && memo.file_committed_at.present?
        begin
          if old_abs.exist? && old_rel.to_s != new_rel.to_s
            @repo.relocate_file!(from_relative: old_rel, to_relative: new_rel)
          end
        rescue MemoRepository::Error => e
          result.git_errors << "memo##{memo.id}: #{e.message}"
        end
      end

      memo.save!(validate: false)
      result.moved += 1
    end

    def cleanup_empty_legacy_directories!(result)
      MemoDirectory.order(:full_path).find_each do |dir|
        next if dir.root?
        next if dir.top_level_bucket?
        next if dir.date_directory?
        next if dir.under_system_space?
        next if dir.full_path.match?(%r{\A(?:home|share|public)/u-\d+\z})
        next if UserSpace.reserved_memo_path?(dir.full_path, dir_parent_account_id(dir))
        next if dir.memos.exists?
        next if dir.children.exists?
        next if dir.boards.exists?
        next if dir.notebooks.exists?

        dir.destroy!
        result.deleted_directories += 1
      rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError => e
        result.errors << "directory##{dir.id} (#{dir.full_path}): #{e.message}"
      end
    end

    def dir_parent_account_id(dir)
      match = dir.full_path.match(%r{\A(?:home|share|public)/u-(\d+)})
      match&.[](1)&.to_i
    end
  end
end
