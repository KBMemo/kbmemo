# frozen_string_literal: true

class ClipCreator
  class Error < StandardError; end

  def initialize(account:, html: nil, url: nil, title: nil, plain: nil)
    @account = account
    @html = html
    @url = url
    @title = title
    @plain = plain
  end

  def call
    metadata = WebPasteMetadata.extract(@html, url: @url, title: @title)
    adoc = build_body(metadata)
    raise Error, "本文が空です。" if adoc.blank?

    directory = MemoDirectory::UserSpace.clippings_directory(@account)
    memo = Memo.new(account: @account, memo_directory: directory, body: adoc)
    memo.properties = clip_properties(metadata)
    apply_title!(memo, metadata)
    memo.save!
    memo
  end

  private

  def build_body(metadata)
    adoc = WebHtmlToAsciidoc.convert(@html.to_s)
    adoc = @plain.to_s.strip if adoc.blank?
    return "" if adoc.blank?

    metadata.url.present? ? WebPasteAttribution.append(adoc, metadata) : adoc
  end

  def clip_properties(metadata)
    {
      "source_url" => metadata.url,
      "source_title" => metadata.title,
      "clipped_at" => Time.current.iso8601
    }.compact
  end

  def apply_title!(memo, metadata)
    if metadata.title.present?
      memo.title = metadata.title
      memo.title_manual = true
      return
    end

    memo.apply_title_from_body_rules!
  end
end
