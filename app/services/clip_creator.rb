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

    directory = MemoDirectory::UserSpace.clippings_directory(@account)
    memo = Memo.new(account: @account, memo_directory: directory)
    memo.properties = clip_properties(metadata)
    WebClipTagging.apply!(memo)
    apply_title!(memo, metadata)
    memo.save!

    body = build_body(memo, metadata)
    raise Error, "本文が空です。" if body.blank?

    memo.update!(body: body)
    memo
  end

  private

  def build_body(memo, metadata)
    adoc = ClipAsciidocProcessor.call(
      html: @html,
      plain: @plain,
      memo: memo,
      source_url: metadata.url
    )
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
