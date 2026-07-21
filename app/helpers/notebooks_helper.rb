# frozen_string_literal: true

module NotebooksHelper
  NOTEBOOK_KIND_LABELS = {
    "blog" => "Blog（公開記事集）",
    "manual" => "Manual Page（手順・ドキュメント）",
    "notes" => "自分用ノート"
  }.freeze

  def notebook_kind_options_for_select
    Notebook.publication_kinds.keys.map { |key| [ NOTEBOOK_KIND_LABELS.fetch(key, key.humanize), key ] }
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

  def notebook_memo_path_for_viewer(notebook, memo, viewer: notebook_show_viewer)
    case viewer
    when :help
      help_path(memo_slug: memo.slug)
    else
      notebook_path(notebook, memo_id: memo.id)
    end
  end

  def notebook_show_viewer
    help_show? ? :help : :notebook
  end

  def notebook_memo_tree_row_classes(entry, selected_memo:)
    active = selected_memo&.id == entry.memo_id
    base = "kb-notebook-tree-link min-w-0 flex-1 #{kb_focus_ring}"
    [ base, active ? "is-active" : "" ].join(" ")
  end

  def notebook_tree_branch_open?(entry, by_parent, selected_memo_id)
    return false unless selected_memo_id

    return true if entry.memo_id == selected_memo_id

    (by_parent[entry.id] || []).any? { |child| notebook_tree_branch_open?(child, by_parent, selected_memo_id) }
  end
end
