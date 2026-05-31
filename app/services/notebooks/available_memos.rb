# frozen_string_literal: true

module Notebooks
  # ノートブック追加ピッカー用のメモ候補。未所属メモに加え、他 NB にある docs_sync 閲覧専用も含める。
  class AvailableMemos
    MAX = 20
    CANDIDATE_POOL = 60

    def self.call(notebook:, user:, query: nil)
      new(notebook: notebook, user: user, query: query).call
    end

    def initialize(notebook:, user:, query: nil)
      @notebook = notebook
      @user = user
      @query = query.to_s.strip
    end

    def call
      rel = MemoPolicy::Scope.new(@user, Memo.all).resolve
        .includes(:tags, :notebook_memo)
        .where.not(id: @notebook.notebook_memos.select(:memo_id))
      rel = rel.search_text(@query) if @query.present?

      rel.order(updated_at: :desc).limit(CANDIDATE_POOL).select { |memo| addable?(memo) }.first(MAX)
    end

    private

    def addable?(memo)
      return false unless MemoPolicy.new(@user, memo).add_to_notebook?

      memo.notebook_memo.nil? || memo.sync_read_only?
    end
  end
end
