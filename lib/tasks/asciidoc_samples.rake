# frozen_string_literal: true

namespace :kbmemo do
  namespace :asciidoc_samples do
    desc <<~DESC.strip
      Upsert AsciiDoc syntax sample memos (from the QR fixture) into the
      "AsciiDoc カバレッジ" notebook and rebuild the checklist note.
      ENV: ACCOUNT_ID, DRY_RUN=1, FIXTURE_PATH
    DESC
    task seed: :environment do
      dry_run = ENV["DRY_RUN"].present?
      result = KbmemoAsciidocSamples::Seed.call(
        account: ENV["ACCOUNT_ID"].presence,
        dry_run: dry_run,
        fixture_path: ENV["FIXTURE_PATH"].presence
      )

      puts "kbmemo:asciidoc_samples:seed#{dry_run ? ' (dry run)' : ''}"
      puts result.summary_lines
      abort "asciidoc_samples:seed finished with errors" if result.errors.any?
    end
  end
end
