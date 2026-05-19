# frozen_string_literal: true

# == Schema Information
#
# Table name: boards
#
#  id                :integer          not null, primary key
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  memo_directory_id :integer
#
# Indexes
#
#  index_boards_on_account_id         (account_id)
#  index_boards_on_memo_directory_id  (memo_directory_id)
#
# Foreign Keys
#
#  account_id         (account_id => accounts.id)
#  memo_directory_id  (memo_directory_id => memo_directories.id)
#
require "test_helper"

class BoardTest < ActiveSupport::TestCase
  test "creates default columns after create" do
    board = Board.create!(title: "Test", account: accounts(:one))
    assert_equal Board::DEFAULT_COLUMN_NAMES, board.board_columns.order(:position).pluck(:name)
  end

  test "destroy clears memo placements without deleting memos" do
    board = boards(:one)
    memo = memos(:one)
    column = board_columns(:one_todo)
    memo.update!(board: board, kanban_column: column, kanban_position: 0)

    assert_difference("Memo.count", 0) do
      board.destroy
    end

    memo.reload
    assert_nil memo.board_id
    assert_nil memo.kanban_column_id
    assert_equal 0, memo.kanban_position
  end
end
