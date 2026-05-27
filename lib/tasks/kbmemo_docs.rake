# frozen_string_literal: true

namespace :kbmemo do
  namespace :docs do
    desc <<~DESC.squish
      Sync docs/**/*.adoc into memos under share/u-{account}/dev-docs/.
      Env: KBMEMO_DOCS_SYNC_ACCOUNT_ID, KBMEMO_DOCS_SYNC_VISIBILITY,
      KBMEMO_DOCS_SYNC_MEMO_GROUP_ID, KBMEMO_DOCS_SYNC_COMMIT=1, DRY_RUN=1
    DESC
    task sync: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
      git_commit = ActiveModel::Type::Boolean.new.cast(ENV["KBMEMO_DOCS_SYNC_COMMIT"])

      result = KbmemoDocs::Sync.call(
        dry_run: dry_run,
        git_commit: git_commit
      )

      puts "kbmemo:docs:sync#{dry_run ? " (dry run)" : ""}"
      result.summary_lines.each { |line| puts line }
      abort "sync finished with errors" if result.errors.any?
    end

    desc <<~DESC.squish
      Register docs_sync memos in the Developer Docs notebook (tree by docs/ path).
      Env: KBMEMO_DOCS_SYNC_ACCOUNT_ID, KBMEMO_DOCS_SYNC_NOTEBOOK_SLUG, DRY_RUN=1
    DESC
    task sync_notebook: :environment do
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])

      result = KbmemoDocs::SyncNotebook.call(dry_run: dry_run)

      puts "kbmemo:docs:sync_notebook#{dry_run ? " (dry run)" : ""}"
      result.summary_lines.each { |line| puts line }
      abort "sync_notebook finished with errors" if result.errors.any?
    end
  end
end
