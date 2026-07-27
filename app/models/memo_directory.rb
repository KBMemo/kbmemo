# frozen_string_literal: true

# == Schema Information
#
# Table name: memo_directories
#
#  id           :bigint           not null, primary key
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
#  fk_rails_...  (parent_id => memo_directories.id)
#
class MemoDirectory < ApplicationRecord
  belongs_to :parent, class_name: "MemoDirectory", optional: true
  has_many :children, class_name: "MemoDirectory", foreign_key: :parent_id, inverse_of: :parent,
    dependent: :restrict_with_exception
  has_many :memos, inverse_of: :memo_directory, dependent: :restrict_with_exception
  has_many :boards, inverse_of: :memo_directory, dependent: :restrict_with_exception

  validates :label, presence: true, allow_blank: true
  validates :full_path, uniqueness: true
  validates :full_path, presence: true, unless: :root?
  validates :path_segment, uniqueness: { scope: :parent_id }, unless: :root?
  validate :path_segment_rules
  validate :path_segment_immutable, on: :update
  validate :parent_and_root_rules
  validate :parent_not_self_or_descendant, if: -> { will_save_change_to_parent_id? }
  validate :parent_not_top_level_bucket, if: :parent_id_changed_for_validation?

  before_validation :normalize_path_segment
  before_validation :assign_default_parent_to_root
  before_validation :compose_full_path

  scope :nav_ordered, -> { order(:full_path) }

  PROTECTED_BUCKET_PATHS = %w[home share public system].freeze
  SYSTEM_PROTECTED_PATHS = %w[system system/docs system/help].freeze
  SYSTEM_FIXED_CHILD_SEGMENTS = %w[docs help].freeze

  def self.ensure_root!
    find_or_create_by!(full_path: "") do |dir|
      dir.path_segment = ""
      dir.label = "ルート"
      dir.parent_id = nil
    end
  end

  def self.root
    ensure_root!
  end

  def root?
    full_path == ""
  end

  def repo_dirname
    root? ? Pathname.new("") : Pathname.new(full_path)
  end

  def display_name
    return "ルート" if root?

    label.presence || path_segment.presence || full_path
  end

  # ルートから各階層のラベル（未設定時は path_segment）を / で連結（例: /Home/user）
  def labeled_path_from_root
    return "/" if root?

    parts = []
    node = self
    while node && !node.root?
      parts.unshift(node.path_segment_label)
      node = node.parent
    end
    "/#{parts.join('/')}"
  end

  def path_segment_label
    label.presence || path_segment
  end

  def date_directory?
    path_segment.match?(MemoDirectory::UserSpace::DATE_PATH_SEGMENT)
  end

  def deletable?
    return false if date_directory?
    return false if protected_from_structure_changes?
    return false if memos_in_subtree?
    return false if boards_in_subtree?
    return false if children.exists?

    true
  end

  def memos_in_subtree?
    Memo.exists?(memo_directory_id: subtree_directory_ids)
  end

  def boards_in_subtree?
    Board.exists?(memo_directory_id: subtree_directory_ids)
  end

  # 削除後にサイドバーで表示を移す先（兄 → 弟 → 親の順）
  def delete_navigation_fallback
    par = parent || self.class.root
    siblings = par.children.order(:full_path).to_a
    index = siblings.index(self)
    return par if index.nil?

    return siblings[index - 1] if index.positive?
    return siblings[index + 1] if index + 1 < siblings.length

    par
  end

  # 親の変更（ディレクトリの移動）が許されるか。保護パスのみ不可（中身の有無は問わない）。
  def reparentable?
    !protected_from_structure_changes?
  end

  # 最上位（ルート）の直下か（home / share / public など）
  def direct_child_of_root?
    !root? && parent_id == self.class.root.id
  end

  # 親ディレクトリの変更 UI を出さない（最上位直下のバケット）
  def parent_selectable?
    !root? && !top_level_bucket?
  end

  # home / share / public / system（最上位バケット）
  def top_level_bucket?
    PROTECTED_BUCKET_PATHS.include?(full_path)
  end

  def under_system_space?
    full_path == "system" || full_path.start_with?("system/")
  end

  # ツリーピッカーで選択可能か（ルート・最上位バケットは不可。system 配下は admin のみ）
  def directory_picker_selectable?(admin: false)
    return false if root? || top_level_bucket?
    return admin if under_system_space?

    true
  end

  alias valid_parent_choice? directory_picker_selectable?

  # ディレクトリ一覧で操作リンクを出さない（ルート・最上位バケット）
  def directory_list_readonly?
    root? || top_level_bucket?
  end

  # 自分と配下ディレクトリの id（親候補から除外する用）
  def subtree_directory_ids
    return [ id ] unless persisted?

    [ id ] + children.flat_map(&:subtree_directory_ids)
  end

  # 親と full_path を更新した直後に、子孫の full_path を再計算して保存する
  # （古い full_path の昇順で処理し、常に親より先に子が来ないようにする）
  def cascade_path_refresh!
    self.class.where(id: subtree_directory_ids - [ id ]).order(:full_path).find_each do |node|
      node.save!
    end
  end

  private

  def protected_from_structure_changes?
    return true if root?
    return true if date_directory?
    return true if PROTECTED_BUCKET_PATHS.include?(full_path)
    return true if SYSTEM_PROTECTED_PATHS.include?(full_path)
    return true if full_path.match?(user_space_root_regex)

    false
  end

  def parent_id_changed_for_validation?
    will_save_change_to_parent_id? || (new_record? && parent_id.present?)
  end

  def parent_not_self_or_descendant
    return if parent_id.blank?
    return unless persisted?

    if parent_id == id
      errors.add(:parent_id, "自分自身にはできません")
      return
    end

    if subtree_directory_ids.include?(parent_id)
      errors.add(:parent_id, "配下のディレクトリへは移せません")
    end
  end

  def parent_not_top_level_bucket
    return if parent.blank?
    return unless parent.top_level_bucket?
    return if parent.full_path == "system" && SYSTEM_FIXED_CHILD_SEGMENTS.include?(path_segment)
    return if user_space_bucket?(parent.full_path) && path_segment.match?(/\Au-\d+\z/)

    errors.add(:parent_id, "Home / Share / Public / System の直下には移せません")
  end

  def user_space_bucket?(full_path)
    %w[home share public].include?(full_path)
  end

  def user_space_root_regex
    @user_space_root_regex ||= /\A(?:#{PROTECTED_BUCKET_PATHS.join('|')})\/u-\d+\z/
  end

  def assign_default_parent_to_root
    return if root?
    return if parent_id.present?

    self.parent = self.class.root
  end

  def compose_full_path
    if root?
      self.full_path = ""
    else
      pf = parent&.full_path.to_s
      seg = path_segment.to_s.strip
      self.full_path = pf.blank? ? seg : "#{pf}/#{seg}"
    end
  end

  def parent_and_root_rules
    return unless root?

    errors.add(:parent, "ルートに親は不要です") if parent_id.present?
    errors.add(:path_segment, "ルートは空にしてください") if path_segment.present?
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
