# frozen_string_literal: true

namespace :memo_slug_git_rename do
  desc <<~DESC.squish
    Preview renaming memo Git work tree files from *-{id}.adoc to uid-suffix slugs.
    Run after db:migrate (MigrateMemoSlugSuffixesToUid). Env: MEMO_GIT_WORK_TREE (optional)
  DESC
  task preview: :environment do
    run_memo_slug_git_rename(dry_run: true)
  end

  desc <<~DESC.squish
    Rename memo Git work tree files from *-{id}.adoc to uid-suffix slugs.
    Env: COMMIT=1 to create a git commit after renames, MEMO_GIT_WORK_TREE (optional)
  DESC
  task apply: :environment do
    run_memo_slug_git_rename(
      dry_run: false,
      git_commit: ActiveModel::Type::Boolean.new.cast(ENV["COMMIT"])
    )
  end
end

def run_memo_slug_git_rename(dry_run:, git_commit: false)
  root = ENV["MEMO_GIT_WORK_TREE"].presence || Rails.application.config.x.memo_git_work_tree
  renamer = MemoSlugGitRename.new(
    repo: MemoRepository.new(root: root),
    dry_run: dry_run,
    git_commit: git_commit
  )

  results = renamer.call
  renamer.summary_lines(results).each { |line| puts line }

  abort "memo_slug_git_rename finished with errors" if results.any? { |r| r.status == :error }
rescue MemoSlugGitRename::Error => e
  abort e.message
end
