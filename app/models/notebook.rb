# frozen_string_literal: true

# == Schema Information
#
# Table name: notebooks
#
#  id                :integer          not null, primary key
#  description       :text             default(""), not null
#  publication_kind  :integer          default("notes"), not null
#  published_at      :datetime
#  slug              :string           not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  memo_directory_id :integer
#
# Indexes
#
#  index_notebooks_on_account_id                       (account_id)
#  index_notebooks_on_account_id_and_publication_kind  (account_id,publication_kind)
#  index_notebooks_on_account_id_and_slug              (account_id,slug) UNIQUE
#  index_notebooks_on_memo_directory_id                (memo_directory_id)
#
# Foreign Keys
#
#  account_id         (account_id => accounts.id)
#  memo_directory_id  (memo_directory_id => memo_directories.id)
#
class Notebook < ApplicationRecord
  GUEST_KINDS = %w[blog manual].freeze

  belongs_to :account
  belongs_to :memo_directory, optional: true

  has_many :notebook_memos, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :notebook
  has_many :memos, through: :notebook_memos

  enum :publication_kind, { blog: 0, manual: 1, notes: 2 }, default: :notes

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :account_id }
  validate :memo_directory_must_be_assignable, if: -> { memo_directory_id.present? }

  before_validation :normalize_slug

  scope :published, -> { where.not(published_at: nil) }
  scope :guest_visible, -> { published.where(publication_kind: GUEST_KINDS) }

  def published?
    published_at.present?
  end

  def guest_visible?
    published? && (blog? || manual?)
  end

  def display_label_for_memo(notebook_memo)
    notebook_memo.chapter_title.presence || notebook_memo.memo.title
  end

  private

  def normalize_slug
    raw = slug.presence || title.to_s
    self.slug = Memo.normalize_slug_fragment(raw) || "notebook"
  end

  def memo_directory_must_be_assignable
    return if memo_directory.nil?
    return if memo_directory.directory_picker_selectable?

    errors.add(:memo_directory, "はメモの保存先として選べません")
  end
end
