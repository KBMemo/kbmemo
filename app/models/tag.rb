# == Schema Information
#
# Table name: tags
#
#  id              :integer          not null, primary key
#  name            :string           not null
#  normalized_name :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_tags_on_normalized_name  (normalized_name) UNIQUE
#
class Tag < ApplicationRecord
  has_many :memo_tags, dependent: :destroy
  has_many :memos, through: :memo_tags

  validates :name, presence: true
  validates :normalized_name, presence: true, uniqueness: true

  before_validation :assign_normalized_name

  def self.resolve_label!(label)
    label = label.to_s.strip
    raise ArgumentError, "tag label is blank" if label.blank?

    normalized = label.downcase
    find_by(normalized_name: normalized) || create!(name: label)
  end

  private

  def assign_normalized_name
    self.normalized_name = name.to_s.downcase.strip if name.present?
  end
end
