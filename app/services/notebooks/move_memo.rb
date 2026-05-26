# frozen_string_literal: true

module Notebooks
  class MoveMemo
    def self.call(notebook:, entry:, parent_id:, position:)
      new(notebook: notebook, entry: entry, parent_id: parent_id, position: position).call
    end

    def initialize(notebook:, entry:, parent_id:, position:)
      @notebook = notebook
      @entry = entry
      @parent_id = parent_id.presence&.to_i
      @position = position.to_i
    end

    def call
      raise Error, "ノートブックに含まれていないメモです" if @entry.notebook_id != @notebook.id

      if @parent_id
        parent = @notebook.notebook_memos.find_by(id: @parent_id)
        raise Error, "親が見つかりません" unless parent
        raise Error, "自分自身の下には移動できません" if parent.id == @entry.id
        raise Error, "子孫の下には移動できません" if parent.descendant_of?(@entry)
      end

      old_parent_id = @entry.parent_id

      ActiveRecord::Base.transaction do
        siblings = @notebook.notebook_memos.where(parent_id: @parent_id).where.not(id: @entry.id).order(:position, :id).to_a
        insert_at = @position.clamp(0, siblings.length)

        @entry.update!(parent_id: @parent_id, position: insert_at)
        renumber!(@parent_id)
        renumber!(old_parent_id) if old_parent_id != @parent_id
      end

      @entry
    end

    private

    def renumber!(parent_id)
      @notebook.notebook_memos.where(parent_id: parent_id).order(:position, :id).each_with_index do |row, index|
        row.update_column(:position, index) if row.position != index
      end
    end
  end
end
