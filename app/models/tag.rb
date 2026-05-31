# == Schema Information
#
# Table name: tags
#
#  id              :bigint           not null, primary key
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

  # このタグの memo_tags をすべて target へ寄せ、自身を削除する。
  # メモがすでに target を持つ場合は重複行だけ削除する。
  def merge_into!(target)
    raise ArgumentError, "target tag is required" if target.nil?
    raise ArgumentError, "cannot merge a tag into itself" if id == target.id

    self.class.transaction do
      MemoTag.where(tag_id: id).find_each do |mt|
        if MemoTag.exists?(memo_id: mt.memo_id, tag_id: target.id)
          mt.destroy!
        else
          mt.update!(tag_id: target.id)
        end
      end
      destroy!
    end
    target.reload
  end

  private

  def assign_normalized_name
    self.normalized_name = name.to_s.downcase.strip if name.present?
  end
end
