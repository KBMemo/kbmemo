# frozen_string_literal: true

class WebClipTagging
  TAG_NAME = "web-clip"
  CLIPPINGS_PATH = %r{\Ahome/u-\d+/clippings(?:/|\z)}
  Result = Data.define(:scanned, :already_tagged, :tagged)

  class << self
    def apply!(memo)
      tag = Tag.resolve_label!(TAG_NAME)
      memo.tags << tag unless memo.tags.include?(tag)
      memo
    end

    def backfill!(dry_run: false)
      scope = existing_clip_memos
      tag = Tag.find_by(normalized_name: TAG_NAME)
      already_tagged = tag ? scope.joins(:memo_tags).where(memo_tags: { tag_id: tag.id }).count : 0
      pending = scope.where.not(id: tag ? MemoTag.where(tag_id: tag.id).select(:memo_id) : [])
      pending_count = pending.count

      unless dry_run
        tag ||= Tag.resolve_label!(TAG_NAME)
        pending.find_each { |memo| memo.tags << tag }
      end

      Result.new(
        scanned: scope.count,
        already_tagged: already_tagged,
        tagged: pending_count
      )
    end

    private

    def existing_clip_memos
      directory_ids = MemoDirectory.select(:id, :full_path).filter_map do |directory|
        directory.id if directory.full_path.match?(CLIPPINGS_PATH)
      end
      Memo.where(memo_directory_id: directory_ids)
    end
  end
end
