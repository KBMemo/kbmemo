# frozen_string_literal: true

module NotebooksHelper
  NOTEBOOK_KIND_LABELS = {
    "blog" => "Blog（公開記事集）",
    "manual" => "Manual Page（手順・ドキュメント）",
    "notes" => "自分用ノート"
  }.freeze

  def notebook_kind_options_for_select
    Notebook.publication_kinds.keys.map { |key| [NOTEBOOK_KIND_LABELS.fetch(key, key.humanize), key] }
  end

  def notebook_kind_label(notebook)
    NOTEBOOK_KIND_LABELS.fetch(notebook.publication_kind, notebook.publication_kind.humanize)
  end

  def notebook_status_label(notebook)
    if notebook.notes?
      "非公開（自分用）"
    elsif notebook.published?
      "公開中"
    else
      "下書き"
    end
  end

  def notebook_memo_path_for_viewer(notebook, memo, viewer:)
    if viewer && policy(memo).update?
      edit_memo_path(memo)
    else
      memo_path(memo)
    end
  end
end
