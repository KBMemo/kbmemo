# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_directories
#
#  id            :integer          not null, primary key
#  label         :string           default(""), not null
#  path_segment  :string           default(""), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_memo_directories_on_path_segment  (path_segment) UNIQUE
#
class MemoDirectory < ApplicationRecord
  has_many :memos, inverse_of: :memo_directory, dependent: :restrict_with_exception

  validates :path_segment, uniqueness: true
  validates :label, presence: true, allow_blank: true

  validate :path_segment_rules
  validate :path_segment_immutable, on: :update

  before_validation :normalize_path_segment

  scope :nav_ordered, -> { order(Arel.sql("CASE WHEN path_segment = '' OR path_segment IS NULL THEN 0 ELSE 1 END"), :path_segment) }

  def self.root
    find_by!(path_segment: "")
  end

  def root?
    path_segment == ""
  end

  def repo_dirname
    root? ? Pathname.new("") : Pathname.new(path_segment)
  end

  def display_name
    return "ルート" if root?

    label.presence || path_segment
  end

  private

  def normalize_path_segment
    self.path_segment = path_segment.to_s.strip.downcase.gsub(%r{[/\\]}, "")
  end

  def path_segment_rules
    if path_segment.blank?
      if new_record?
        errors.add(:path_segment, "を入力してください（例: work, ideas）")
      elsif MemoDirectory.where(path_segment: "").where.not(id: id).exists?
        errors.add(:path_segment, "は一意のルート用のみ空にできます")
      end
    elsif !path_segment.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
      errors.add(:path_segment, "は英小文字・数字・ハイフンのみ使えます")
    end
  end

  def path_segment_immutable
    errors.add(:path_segment, "は作成後に変更できません") if will_save_change_to_path_segment?
  end
end
