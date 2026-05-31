# frozen_string_literal: true

# == Schema Information
#
# Table name: board_columns
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  board_id   :integer          not null
#
# Indexes
#
#  index_board_columns_on_board_id               (board_id)
#  index_board_columns_on_board_id_and_position  (board_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (board_id => boards.id)
#
class BoardColumn < ApplicationRecord
  belongs_to :board
  has_many :memos, foreign_key: :kanban_column_id, dependent: :nullify, inverse_of: :kanban_column

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, uniqueness: { scope: :board_id }

  def swap_position_with!(other)
    raise ArgumentError, "columns must belong to the same board" unless other.board_id == board_id

    BoardColumn.transaction do
      my_pos = position
      other_pos = other.position
      update_column(:position, -1)
      other.update_column(:position, my_pos)
      update_column(:position, other_pos)
    end
  end
end
