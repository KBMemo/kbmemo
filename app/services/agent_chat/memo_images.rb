# frozen_string_literal: true

module AgentChat
  # 可視メモに保存された画像を AI チャットの添付候補として扱う。
  class MemoImages
    MAX_MEMOS = 20
    MAX_IMAGES = 50

    Entry = Data.define(:memo, :relative_path) do
      def as_json
        {
          memo_id: memo.id,
          memo_title: memo.title,
          directory: memo.memo_directory.labeled_path_from_root,
          filename: File.basename(relative_path),
          relative_path: relative_path,
          preview_url: MemoAssets.asset_url_for(memo, relative_path),
          updated_at: memo.updated_at.iso8601
        }
      end
    end

    UploadFile = Data.define(:io, :original_filename, :content_type) do
      delegate :read, :rewind, :size, to: :io
    end

    def self.list(scope:, query:, memo_ids: nil, repo: MemoRepository.new)
      memo_scope = scope.includes(:memo_directory).order(updated_at: :desc)
      normalized_ids = Array(memo_ids).filter_map { |id| Integer(id, exception: false) }.uniq
      memo_scope = memo_scope.where(id: normalized_ids) if memo_ids
      memo_scope = memo_scope.search_text(query) if query.present?

      memo_scope.limit(MAX_MEMOS).flat_map do |memo|
        MemoAttachments.list(memo, body: memo.body, repo: repo)
          .select { |entry| entry.kind == :image }
          .map { |entry| Entry.new(memo:, relative_path: entry.relative_path) }
      end.first(MAX_IMAGES)
    end

    def self.upload(memo:, relative_path:, cookie_header:, repo: MemoRepository.new)
      path = MemoAssets.resolve_path!(memo, relative_path, repo: repo)
      content_type = Marcel::MimeType.for(path).to_s.downcase
      unless MemoAssets::ALLOWED_CONTENT_TYPES.include?(content_type)
        raise MemoAssets::InvalidFile, "対応していない画像形式です。"
      end
      raise MemoAssets::InvalidFile, "10MB 以下の画像にしてください。" if path.size > MemoAssets::MAX_BYTES

      File.open(path, "rb") do |io|
        file = UploadFile.new(
          io: io,
          original_filename: File.basename(path),
          content_type: content_type
        )
        TsuzuraUpload.call(file:, cookie_header:)
      end
    end
  end
end
