# frozen_string_literal: true

# == Schema Information
#
# Table name: notebook_memos
#
#  id            :integer          not null, primary key
#  chapter_title :string
#  position      :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  memo_id       :integer          not null
#  notebook_id   :integer          not null
#  parent_id     :integer
#
# Indexes
#
#  index_notebook_memos_on_memo_id                   (memo_id)
#  index_notebook_memos_on_notebook_id               (notebook_id)
#  index_notebook_memos_on_notebook_id_and_memo_id   (notebook_id,memo_id) UNIQUE
#  index_notebook_memos_on_notebook_parent_position  (notebook_id,parent_id,position)
#  index_notebook_memos_on_parent_id                 (parent_id)
#
# Foreign Keys
#
#  memo_id      (memo_id => memos.id)
#  notebook_id  (notebook_id => notebooks.id)
#  parent_id    (parent_id => notebook_memos.id)
#
class NotebookMemo < ApplicationRecord
  belongs_to :notebook
  belongs_to :memo
  belongs_to :parent, class_name: "NotebookMemo", optional: true, inverse_of: :children

  has_many :children, -> { order(:position, :id) },
    class_name: "NotebookMemo", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent

  validates :memo_id, uniqueness: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :parent_must_belong_to_same_notebook
  validate :parent_must_not_be_self_or_descendant

  def descendant_of?(other)
    return false if other.nil?

    parent_id = self.parent_id
    seen = {}
    while parent_id.present?
      return true if parent_id == other.id
      break if seen[parent_id]

      seen[parent_id] = true
      parent_id = self.class.where(id: parent_id).pick(:parent_id)
    end
    false
  end

  private

  def parent_must_belong_to_same_notebook
    return if parent.nil?

    errors.add(:parent, "は同じノートブック内である必要があります") if parent.notebook_id != notebook_id
  end

  def parent_must_not_be_self_or_descendant
    return if parent.nil? || parent_id == id

    errors.add(:parent, "に自分自身や子孫は指定できません") if parent_id == id || parent.descendant_of?(self)
  end
end
