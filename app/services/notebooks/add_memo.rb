# frozen_string_literal: true

module Notebooks
  class AddMemo
    def self.call(notebook:, memo:, parent_id: nil)
      new(notebook: notebook, memo: memo, parent_id: parent_id).call
    end

    def initialize(notebook:, memo:, parent_id: nil)
      @notebook = notebook
      @memo = memo
      @parent_id = parent_id.presence
    end

    def call
      existing = @memo.notebook_memo
      if existing.present? && existing.notebook_id != @notebook.id
        if @memo.docs_sync_read_only?
          existing.destroy!
        else
          raise Error, "このメモは既に別のノートブックに含まれています"
        end
      end

      position = @notebook.notebook_memos.where(parent_id: @parent_id).maximum(:position).to_i + 1
      NotebookMemo.find_or_initialize_by(notebook: @notebook, memo: @memo).tap do |entry|
        if entry.new_record?
          entry.parent_id = @parent_id
          entry.position = position
        end
        entry.save!
      end
    end
  end
end
