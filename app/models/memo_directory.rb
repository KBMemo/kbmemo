# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_directories
#
#  id           :integer          not null, primary key
#  full_path    :string           not null
#  label        :string           default(""), not null
#  path_segment :string           default(""), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  parent_id    :integer
#
# Indexes
#
#  index_memo_directories_on_full_path  (full_path) UNIQUE
#  index_memo_directories_on_parent_id  (parent_id)
#
# Foreign Keys
#
#  parent_id  (parent_id => memo_directories.id)
#
class MemoDirectory < ApplicationRecord
  belongs_to :parent, class_name: "MemoDirectory", optional: true
  has_many :children, class_name: "MemoDirectory", foreign_key: :parent_id, inverse_of: :parent,
    dependent: :restrict_with_exception
  has_many :memos, inverse_of: :memo_directory, dependent: :restrict_with_exception

  validates :label, presence: true, allow_blank: true
  validates :full_path, presence: true, uniqueness: true
  validates :path_segment, uniqueness: { scope: :parent_id }, unless: :root?
  validate :path_segment_rules
  validate :path_segment_immutable, on: :update
  validate :parent_and_root_rules

  before_validation :normalize_path_segment
  before_validation :compose_full_path

  scope :nav_ordered, -> { order(:full_path) }

  PROTECTED_BUCKET_PATHS = %w[home share public].freeze

  def self.root
    find_by!(full_path: "")
  end

  def root?
    full_path == ""
  end

  def repo_dirname
    root? ? Pathname.new("") : Pathname.new(full_path)
  end

  def display_name
    return "ルート" if root?

    label.presence || full_path.presence || path_segment
  end

  def deletable?
    return false if root?
    return false if PROTECTED_BUCKET_PATHS.include?(full_path)
    return false if full_path.match?(user_space_root_regex)

    true
  end

  private

  def user_space_root_regex
    @user_space_root_regex ||= /\A(?:#{PROTECTED_BUCKET_PATHS.join('|')})\/u-\d+\z/
  end

  def compose_full_path
    if parent.nil?
      self.full_path = path_segment.to_s.strip.present? ? path_segment : ""
    else
      pf = parent.full_path
      seg = path_segment.to_s.strip
      self.full_path = pf.blank? ? seg : "#{pf}/#{seg}"
    end
  end

  def parent_and_root_rules
    if root?
      errors.add(:parent, "ルートに親は不要です") if parent_id.present?
      errors.add(:path_segment, "ルートは空にしてください") if path_segment.present?
    elsif parent_id.blank?
      errors.add(:parent, "を指定してください")
    end
  end

  def normalize_path_segment
    self.path_segment = path_segment.to_s.strip.downcase.gsub(%r{[/\\]}, "")
  end

  def path_segment_rules
    return if root?

    if path_segment.blank?
      errors.add(:path_segment, "を入力してください（例: work, ideas）")
    elsif !path_segment.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
      errors.add(:path_segment, "は英小文字・数字・ハイフンのみ使えます")
    end
  end

  def path_segment_immutable
    errors.add(:path_segment, "は作成後に変更できません") if will_save_change_to_path_segment?
  end
end
