# frozen_string_literal: true

module NotebookShowSupport
  extend ActiveSupport::Concern

  private

  def load_notebook_show!(notebook)
    @notebook = notebook
    load_notebook_memo_tree
    @can_manage = rodauth.rails_account.present? && policy(@notebook).manage_memos?
    @selected_memo = find_selected_notebook_memo
  end

  def load_notebook_memo_tree
    entries = @notebook.notebook_memos
      .joins(:memo)
      .merge(policy_scope(Memo))
      .includes(:memo)
      .order(:position, :id)
      .to_a

    @notebook_memos_by_parent = entries.group_by(&:parent_id)
    @notebook_memo_roots = @notebook_memos_by_parent[nil] || []
    @notebook_memos = entries
  end

  def find_selected_notebook_memo
    scope = policy_scope(Memo).joins(:notebook_memo).where(notebook_memos: { notebook_id: @notebook.id })

    if params[:memo_slug].present?
      slug = params[:memo_slug].to_s
      memo = scope.find_by(slug: slug)
      return memo if memo
    end

    if params[:memo_id].present?
      memo = scope.find_by(id: params[:memo_id])
      return memo if memo
    end

    @notebook_memo_roots.first&.memo
  end
end
