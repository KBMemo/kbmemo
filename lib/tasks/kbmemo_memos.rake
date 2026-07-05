# frozen_string_literal: true

namespace :kbmemo do
  namespace :memos do
    desc "Preview relocating memos to home/u-{id}/YYYY-MM-DD by created_at (dry-run)"
    task relocate_by_created_at_preview: :environment do
      run_relocate_by_created_at(dry_run: true)
    end

    desc <<~DESC.squish
      Relocate memos to home/u-{id}/YYYY-MM-DD by created_at and delete empty legacy directories.
      Env: GIT_RELOCATE=0 to skip Git file moves
    DESC
    task relocate_by_created_at: :environment do
      run_relocate_by_created_at(
        dry_run: false,
        git_relocate: ActiveModel::Type::Boolean.new.cast(ENV.fetch("GIT_RELOCATE", "1"))
      )
    end
  end
end

def run_relocate_by_created_at(dry_run:, git_relocate: true)
  result = MemoDirectory::RelocateByCreatedAt.call(dry_run: dry_run, git_relocate: git_relocate)
  MemoDirectory::RelocateByCreatedAt.new(dry_run: dry_run, git_relocate: git_relocate)
    .summary_lines(result).each { |line| puts line }

  abort "relocate_by_created_at finished with errors" if result.errors.any?
end
