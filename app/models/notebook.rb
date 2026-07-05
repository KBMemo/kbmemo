# frozen_string_literal: true

# == Schema Information
#
# Table name: notebooks
#
#  id               :bigint           not null, primary key
#  description      :text             default(""), not null
#  publication_kind :integer          default("notes"), not null
#  published_at     :datetime
#  slug             :string           not null
#  title            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :integer          not null
#
# Indexes
#
#  index_notebooks_on_account_id                       (account_id)
#  index_notebooks_on_account_id_and_publication_kind  (account_id,publication_kind)
#  index_notebooks_on_account_id_and_slug              (account_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Notebook < ApplicationRecord
  GUEST_KINDS = %w[blog manual].freeze

  belongs_to :account

  has_many :notebook_memos, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :notebook
  has_many :root_notebook_memos, -> { where(parent_id: nil).order(:position, :id) },
    class_name: "NotebookMemo", inverse_of: :notebook
  has_many :memos, through: :notebook_memos

  enum :publication_kind, { blog: 0, manual: 1, notes: 2 }, default: :notes

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :account_id }

  before_validation :normalize_slug

  scope :published, -> { where.not(published_at: nil) }
  scope :guest_visible, -> { published.where(publication_kind: GUEST_KINDS) }
  scope :order_by_latest_memo_updated_at, lambda {
    left_joins(:memos)
      .group("notebooks.id")
      .order(Arel.sql("MAX(memos.updated_at) DESC NULLS LAST"))
  }

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
end
