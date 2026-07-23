# frozen_string_literal: true

namespace :kbmemo do
  namespace :clips do
    desc "Preview adding the web-clip tag to existing memos under clippings directories"
    task tag_existing_preview: :environment do
      print_web_clip_tagging_result(WebClipTagging.backfill!(dry_run: true), dry_run: true)
    end

    desc "Add the web-clip tag to existing memos under clippings directories"
    task tag_existing: :environment do
      print_web_clip_tagging_result(WebClipTagging.backfill!)
    end
  end
end

def print_web_clip_tagging_result(result, dry_run: false)
  prefix = dry_run ? "[dry-run] " : ""
  puts "#{prefix}scanned=#{result.scanned} already_tagged=#{result.already_tagged} tagged=#{result.tagged}"
end
