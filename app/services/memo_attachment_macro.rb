# frozen_string_literal: true

# attachment::report.pdf[] を認可済みのメモ asset URL へのリンクに展開する。
class MemoAttachmentMacro
  ATTACHMENT_MACRO = /attachment::([^\[\]\s]+)(\[[^\]]*\])?/

  def initialize(memo:, repo: MemoRepository.new)
    @memo = memo
    @repo = repo
  end

  def substitute(text)
    return text if text.blank? || !@memo&.persisted?

    out = +""
    in_fenced = false
    text.each_line do |line|
      if line.match?(/\A```/)
        in_fenced = !in_fenced
        out << line
      elsif in_fenced
        out << line
      else
        out << line.gsub(ATTACHMENT_MACRO) { replace_attachment(Regexp.last_match(1), Regexp.last_match(2)) }
      end
    end
    out
  end

  private

  def replace_attachment(raw_path, attrs)
    relative = MemoAssetPath.existing_relative!(raw_path)
    path = MemoAssets.resolve_path!(@memo, relative, repo: @repo)
    raise MemoAssets::InvalidFile unless MemoAssets.document?(path.basename.to_s)

    label = attrs.to_s.delete_prefix("[").delete_suffix("]").presence || File.basename(relative)
    "link:#{MemoAssets.asset_url_for(@memo, relative)}[#{label}]"
  rescue MemoAssets::InvalidFile
    "[.memo-attachment-missing]##{escape(raw_path)}#"
  end

  def escape(text)
    text.to_s.gsub("#", '\\#')
  end
end
