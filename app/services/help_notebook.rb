# frozen_string_literal: true

# 公開ヘルプ用 Notebook（/help）の解決。
module HelpNotebook
  DEFAULT_SLUG = "help"

  module_function

  def slug
    ENV.fetch("KBMEMO_HELP_NOTEBOOK_SLUG", DEFAULT_SLUG)
  end

  def find
    Notebook.guest_visible.find_by(slug: slug)
  end

  def find!
    find || raise(ActiveRecord::RecordNotFound, "published help notebook not found (slug=#{slug})")
  end
end
