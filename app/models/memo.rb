# == Schema Information
#
# Table name: memos
#
#  id           :integer          not null, primary key
#  body         :text             default(""), not null
#  properties   :json             not null
#  slug         :string
#  title        :string           not null
#  title_manual :boolean          default(FALSE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_memos_on_slug  (slug) UNIQUE
#
class Memo < ApplicationRecord
  TITLE_PLACEHOLDER = " - 未入力 - ".freeze

  has_many :memo_tags, dependent: :destroy
  has_many :tags, through: :memo_tags

  validates :title, presence: true
  validates :slug, uniqueness: { allow_blank: true }

  before_validation :normalize_unfilled_title_marker
  before_validation :prepare_title_from_body_and_manual
  before_save -> { self.slug = slug.presence }

  # 本文1行目から一覧用タイトルを派生（行頭の連続する "=" と続く空白を除く）。title_manual が true のときは同期しない。
  def self.derived_title_from_body(body)
    line = body.to_s.lines(chomp: true).first
    line = line.to_s.strip
    line = line.sub(/\A=+\s*/, "")
    line.presence || TITLE_PLACEHOLDER
  end

  def self.title_unfilled_value?(value)
    value.to_s.strip.blank? || value.to_s == TITLE_PLACEHOLDER
  end

  def title_unfilled?
    self.class.title_unfilled_value?(title)
  end

  # Comma-separated labels; assigns tags before or after save via association.
  def assign_tags_from_list(list_string)
    labels = list_string.to_s.split(/[,，]/).map(&:strip).reject(&:blank?).uniq
    self.tags = labels.map { |label| Tag.resolve_label!(label) }.uniq
  end

  # save(validate: false) では before_validation が実行されないため、ドラフト保存前に明示する
  def apply_title_from_body_rules!
    prepare_title_from_body_and_manual
  end

  private

  def normalize_unfilled_title_marker
    self.title = self.class::TITLE_PLACEHOLDER if self.class.title_unfilled_value?(title)
  end

  def prepare_title_from_body_and_manual
    unless title_manual?
      d = self.class.derived_title_from_body(body)
      # このリクエストで title を変更していて、かつ派生タイトルと違えば手動扱い（ドラフト本文のみ更新では title は変わらない）
      self.title_manual = true if title_changed? && !self.class.title_unfilled_value?(title) && title.to_s.strip != d
    end
    unless title_manual?
      self.title = self.class.derived_title_from_body(body)
    end
  end
end
