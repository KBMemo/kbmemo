# frozen_string_literal: true

# == Schema Information
#
# Table name: boards
#
#  id                :bigint           not null, primary key
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
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (memo_directory_id => memo_directories.id)
#
class Board < ApplicationRecord
  DEFAULT_COLUMN_NAMES = %w[Todo Doing Done].freeze

  belongs_to :account
  belongs_to :memo_directory, optional: true

  has_many :board_columns, -> { order(:position) }, dependent: :destroy, inverse_of: :board
  has_many :memos, dependent: :nullify

  validates :title, presence: true
  validate :memo_directory_must_be_assignable, if: -> { memo_directory_id.present? }

  after_create :create_default_columns!
  before_destroy :clear_memo_placements

  def default_memo_directory_for(account)
    memo_directory || MemoDirectory::UserSpace.default_home_directory(account)
  end

  private

  def create_default_columns!
    DEFAULT_COLUMN_NAMES.each_with_index do |name, index|
      board_columns.create!(name: name, position: index)
    end
  end

  def clear_memo_placements
    memos.update_all(board_id: nil, kanban_column_id: nil, kanban_position: 0)
  end

  def memo_directory_must_be_assignable
    return if memo_directory.nil?
    return if memo_directory.directory_picker_selectable?(admin: account&.admin?)

    errors.add(:memo_directory, "はメモの保存先として選べません")
  end
end
