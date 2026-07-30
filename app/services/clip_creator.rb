# frozen_string_literal: true

class ClipCreator
  class Error < StandardError; end

  MODES = %w[selection article summary].freeze

  def initialize(account:, html: nil, url: nil, title: nil, plain: nil, mode: "selection")
    @account = account
    @html = html
    @url = url
    @title = title
    @plain = plain
    @mode = MODES.include?(mode.to_s) ? mode.to_s : "selection"
  end

  def call
    Memo.transaction do
      metadata = WebPasteMetadata.extract(@html, url: @url, title: @title)

      directory = MemoDirectory::UserSpace.clippings_directory(@account)
      memo = Memo.new(account: @account, memo_directory: directory)
      memo.properties = clip_properties(metadata)
      apply_title!(memo, metadata)
      memo.save!
      WebClipTagging.apply!(memo)

      body = build_body(memo, metadata)
      raise Error, "本文が空です。" if body.blank?

      memo.update!(body: body)
      memo
    end
  end

  private

  def build_body(memo, metadata)
    source_html = @mode == "selection" ? @html : ClipArticleExtractor.extract(@html)
    if @mode == "summary"
      prepared = ClipHtmlPreparer.prepare(source_html)
      source = PandocHtmlToAsciidoc.convert(prepared).strip
      return ClipSummarizer.call(account: @account, content: source)
    end

    adoc = ClipAsciidocProcessor.call(
      html: source_html,
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
      "clipped_at" => Time.current.iso8601,
      "clip_mode" => @mode
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
