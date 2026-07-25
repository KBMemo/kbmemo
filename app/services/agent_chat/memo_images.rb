# frozen_string_literal: true

module AgentChat
  # 可視メモに保存された画像を AI チャットの添付候補として扱う。
  class MemoImages
    class InvalidCursor < StandardError; end

    PAGE_SIZE = 30
    MEMO_BATCH_SIZE = 20
    CURSOR_PURPOSE = "agent-chat-memo-images"

    Page = Data.define(:entries, :next_cursor)

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

    def self.list(scope:, query:, memo_ids: nil, cursor: nil, repo: MemoRepository.new)
      query = query.to_s.strip
      normalized_ids = normalize_memo_ids(memo_ids)
      cursor_data = decode_cursor(cursor, query:, memo_ids: normalized_ids)
      memo_scope = scope.includes(:memo_directory).order(updated_at: :desc, id: :desc)
      memo_scope = memo_scope.where(id: normalized_ids) if memo_ids
      memo_scope = memo_scope.search_text(query) if query.present?
      memo_scope = scope_from_cursor(memo_scope, cursor_data) if cursor_data

      entries = []
      loop do
        memos = memo_scope.limit(MEMO_BATCH_SIZE).to_a
        break if memos.empty?

        memos.each do |memo|
          memo_entries = image_entries(memo, repo:)
          if cursor_data && memo.id == cursor_data.fetch("memo_id")
            memo_entries = memo_entries.drop_while do |entry|
              entry.relative_path <= cursor_data.fetch("relative_path")
            end
          end
          entries.concat(memo_entries)
          if entries.size > PAGE_SIZE
            return page_with_cursor(entries.first(PAGE_SIZE), query:, memo_ids: normalized_ids)
          end
        end

        last_memo = memos.last
        memo_scope = scope_after_memo(memo_scope, last_memo)
        cursor_data = nil
      end

      Page.new(entries: entries, next_cursor: nil)
    end

    def self.normalize_memo_ids(memo_ids)
      Array(memo_ids).filter_map { |id| Integer(id, exception: false) }.uniq
    end
    private_class_method :normalize_memo_ids

    def self.image_entries(memo, repo:)
      MemoAttachments.list(memo, body: memo.body, repo: repo)
        .select { |entry| entry.kind == :image }
        .map { |entry| Entry.new(memo:, relative_path: entry.relative_path) }
        .sort_by(&:relative_path)
    end
    private_class_method :image_entries

    def self.scope_from_cursor(scope, cursor)
      updated_at = Time.iso8601(cursor.fetch("memo_updated_at"))
      scope.where(
        "memos.updated_at < :updated_at OR (memos.updated_at = :updated_at AND memos.id <= :memo_id)",
        updated_at: updated_at,
        memo_id: cursor.fetch("memo_id")
      )
    rescue ArgumentError, KeyError
      raise InvalidCursor, "画像一覧のカーソルが不正です。"
    end
    private_class_method :scope_from_cursor

    def self.scope_after_memo(scope, memo)
      scope.where(
        "memos.updated_at < :updated_at OR (memos.updated_at = :updated_at AND memos.id < :memo_id)",
        updated_at: memo.updated_at,
        memo_id: memo.id
      )
    end
    private_class_method :scope_after_memo

    def self.page_with_cursor(entries, query:, memo_ids:)
      last = entries.last
      Page.new(
        entries: entries,
        next_cursor: cursor_verifier.generate(
          {
            "memo_updated_at" => last.memo.updated_at.iso8601(6),
            "memo_id" => last.memo.id,
            "relative_path" => last.relative_path,
            "filters" => cursor_filters(query:, memo_ids:)
          },
          purpose: CURSOR_PURPOSE
        )
      )
    end
    private_class_method :page_with_cursor

    def self.decode_cursor(cursor, query:, memo_ids:)
      return nil if cursor.blank?

      payload = cursor_verifier.verify(cursor, purpose: CURSOR_PURPOSE)
      unless payload["filters"] == cursor_filters(query:, memo_ids:)
        raise InvalidCursor, "検索条件が変更されています。最初から読み込み直してください。"
      end

      payload
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidCursor, "画像一覧のカーソルが不正です。"
    end
    private_class_method :decode_cursor

    def self.cursor_filters(query:, memo_ids:)
      { "query" => query, "memo_ids" => memo_ids }
    end
    private_class_method :cursor_filters

    def self.cursor_verifier
      Rails.application.message_verifier(CURSOR_PURPOSE)
    end
    private_class_method :cursor_verifier

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
