# == Schema Information
#
# Table name: memos
#
#  id                :bigint           not null, primary key
#  body              :text             default(""), not null
#  file_committed_at :datetime
#  kanban_position   :integer          default(0), not null
#  properties        :jsonb            not null
#  slug              :string
#  slug_manual       :boolean          default(FALSE), not null
#  title             :string           not null
#  title_manual      :boolean          default(FALSE), not null
#  uid               :string           not null
#  visibility        :integer          default("owner_read_write"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  board_id          :integer
#  kanban_column_id  :integer
#  memo_directory_id :integer          not null
#  memo_group_id     :integer
#
# Indexes
#
#  index_memos_on_account_id         (account_id)
#  index_memos_on_board_id           (board_id)
#  index_memos_on_kanban_column_id   (kanban_column_id)
#  index_memos_on_memo_directory_id  (memo_directory_id)
#  index_memos_on_memo_group_id      (memo_group_id)
#  index_memos_on_slug               (slug) UNIQUE
#  index_memos_on_uid                (uid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (board_id => boards.id)
#  fk_rails_...  (kanban_column_id => board_columns.id)
#  fk_rails_...  (memo_directory_id => memo_directories.id)
#  fk_rails_...  (memo_group_id => memo_groups.id)
#
class Memo < ApplicationRecord
  include MemoPropertyOptions
  include MemoGoogleCalendar

  TITLE_PLACEHOLDER = " - 未入力 - ".freeze

  belongs_to :memo_directory
  belongs_to :account
  belongs_to :memo_group, optional: true
  belongs_to :board, optional: true
  belongs_to :kanban_column, class_name: "BoardColumn", optional: true

  has_many :memo_tags, dependent: :destroy
  has_many :tags, through: :memo_tags
  has_many :outgoing_wiki_links, class_name: "MemoWikiLink", foreign_key: :source_memo_id, dependent: :delete_all, inverse_of: :source_memo
  has_many :incoming_wiki_links, class_name: "MemoWikiLink", foreign_key: :target_memo_id, dependent: :delete_all, inverse_of: :target_memo
  has_many :memo_view_histories, dependent: :delete_all
  has_one :notebook_memo, dependent: :destroy
  has_one :notebook, through: :notebook_memo

  scope :on_kanban_board, -> { where.not(board_id: nil) }
  scope :available_for_board, -> { where(board_id: nil) }

  scope :search_text, lambda { |query|
    q = query.to_s.strip
    next all if q.blank?

    if pgroonga_search?
      where("(title || E'\\n' || body) &@~ ?", q)
        .order(Arel.sql("pgroonga_score(tableoid, ctid) DESC"))
    else
      pattern = "%#{sanitize_sql_like(q)}%"
      where("LOWER(title) LIKE LOWER(?) OR LOWER(body) LIKE LOWER(?)", pattern, pattern)
    end
  }

  def self.pgroonga_search?
    return @pgroonga_search if defined?(@pgroonga_search)

    @pgroonga_search = connection.select_value(
      "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'pgroonga')"
    )
  rescue StandardError
    @pgroonga_search = false
  end

  def self.reset_pgroonga_search_cache!
    remove_instance_variable(:@pgroonga_search) if defined?(@pgroonga_search)
  end

  # 0: 全体（未ログイン含む閲覧可） 1: グループ閲覧のみ 3: グループ内読み書き 4: 自分のみ読み書き
  # （旧「自分のみ閲覧」はオーナー更新と重複するため廃止。DB の 2 はマイグレーションで 4 に寄せた）
  enum :visibility, {
    public_everyone: 0,
    group_read: 1,
    group_read_write: 3,
    owner_read_write: 4
  }

  # ULID（Crockford Base32, 26 桁・大文字）。クライアント生成可能な安定識別子。
  UID_FORMAT = /\A[0-9A-HJKMNP-TV-Z]{26}\z/
  # スラッグ末尾の識別子サフィックス。レガシーの数値 id（-42）または ULID（-{ulid}）。
  # normalize_slug_fragment で小文字化されるため大文字小文字を問わない。
  SLUG_TRAILING_ID = /-(?:\d+|[0-9A-HJKMNP-TV-Z]{26})\z/i

  validates :title, presence: true
  validates :slug, uniqueness: { allow_blank: true }
  validates :uid, presence: true, uniqueness: true, format: { with: UID_FORMAT }
  validates :memo_group_id, presence: true, if: -> { group_read? || group_read_write? }
  validate :memo_group_must_include_owner, if: -> { group_read? || group_read_write? }
  validate :memo_directory_must_be_assignable_location
  validate :kanban_placement_consistency

  before_validation :assign_uid
  before_validation :assign_default_memo_directory
  before_validation :clear_memo_group_when_not_group_visibility
  before_validation :normalize_unfilled_title_marker
  before_validation :prepare_title_from_body_and_manual
  before_validation :prepare_slug_from_title_and_manual
  before_validation :normalize_slug_for_storage
  before_create :assign_uid
  after_commit :reindex_outgoing_wiki_links, on: %i[create update], if: :memo_wiki_links_need_outgoing_reindex?
  after_commit :reindex_inbound_wiki_links, on: :update, if: :memo_wiki_links_need_inbound_reindex?

  # 保存時のスラッグ（パス用）。空は nil。MemoRepository のファイル名と揃える。
  def self.normalize_slug_fragment(value)
    raw = value.to_s.strip.gsub(%r{[/\\]}, "")
    raw.parameterize(separator: "-").presence
  end

  # 末尾の識別子（数値 id または ULID）を除いたスラッグ本体（Wiki リンクのレガシー表記との互換用）。
  def self.slug_stem(value, memo_id: nil, uid: nil)
    frag = normalize_slug_fragment(value)
    return nil if frag.blank?

    stem = frag.sub(SLUG_TRAILING_ID, "")
    stem = stem.sub(/-#{Regexp.escape(memo_id.to_s)}\z/, "") if memo_id.present?
    if uid.present?
      suffix = slug_suffix_for(uid)
      stem = stem.sub(/-#{Regexp.escape(suffix)}\z/i, "") if suffix.present?
    end
    stem.presence || "memo"
  end

  # uid を slug 末尾に使うための正規化（小文字・パス安全）。
  def self.slug_suffix_for(uid)
    normalize_slug_fragment(uid.to_s.upcase)
  end

  # アプリ全体で一意なスラッグ（Wiki リンク・Git ファイル名）。例: first-memo-01kdwpv...
  def self.global_slug_for(stem, uid)
    suffix = slug_suffix_for(uid)
    return slug_stem(stem, uid: uid) if suffix.blank?

    "#{slug_stem(stem, uid: uid)}-#{suffix}"
  end

  # 本文1行目から一覧用タイトルを派生（行頭の連続する "=" と続く空白を除く）。title_manual が true のときは同期しない。
  def self.derived_title_from_body(body)
    line = body.to_s.lines(chomp: true).first
    line = line.to_s.strip
    line = line.sub(/\A=+\s*/, "")
    line.presence || TITLE_PLACEHOLDER
  end

  def self.title_unfilled_value?(value)
    s = value.to_s.strip
    return true if s.blank?
    return true if s == TITLE_PLACEHOLDER
    # strip 後はスペース位置が変わるため、空白を除いて「未入力」プレースホルダーと比較する
    s.gsub(/\s+/, "") == TITLE_PLACEHOLDER.gsub(/\s+/, "")
  end

  def title_unfilled?
    self.class.title_unfilled_value?(title)
  end

  # 一覧・プレビュー文言など UI 用。未コミット、またはファイル保存後に DB が更新されている＝再編集ドラフト。
  # スラッグ自動同期の可否は file_committed_at? のまま（一度コミットしたら維持）。
  def display_as_draft?
    return false if sync_read_only?

    return true if file_committed_at.blank?

    updated_at > file_committed_at
  end

  # 画像アセットのアップロード可否（Git へ初回コミット済みか）。
  # persisted? だけではドラフト自動保存済み・未コミットも true になるため file_committed_at を見る。
  # 再編集ドラフト（display_as_draft? かつ file_committed_at あり）は true のまま。
  def image_assets_uploadable?
    persisted? && file_committed_at.present?
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

  def apply_slug_from_title_rules!
    prepare_slug_from_title_and_manual
  end

  # save(validate: false) のドラフト保存でも slug の正規化・ID 付与を行う
  def apply_storage_slug!
    normalize_slug_for_storage
  end

  # ファイルにコミットする前はタイトルから派生。file_committed_at があればスラッグは手動同期ルールへ（一度コミットしたら維持）。
  # file_committed_at は最終コミット時の updated_at と揃え、一覧の「再編集ドラフト」表示に使う。
  # 日本語など parameterize が空のときは memo-{id} にフォールバック（一意・ファイル名用）。
  # 英字と日本語が混在すると parameterize は日本語を落とすだけの断片を返すため、その場合は MeCab 経路を優先する。
  def self.derived_slug_from_title(title, memo = nil)
    t = title.to_s.strip
    return nil if title_unfilled_value?(t)

    if title_includes_japanese_script?(t)
      romaji = MemoMecabRomaji.romaji_slug_from(t)
      seg = normalize_slug_fragment(romaji) if romaji.present?
      return seg if seg.present?

      return "memo"
    end

    seg = t.parameterize(separator: "-").presence
    return seg if seg.present?

    romaji = MemoMecabRomaji.romaji_slug_from(t)
    seg = normalize_slug_fragment(romaji) if romaji.present?
    return seg if seg.present?

    "memo"
  end

  def self.title_includes_japanese_script?(text)
    text.match?(/\p{Hiragana}|\p{Katakana}|\p{Han}|\uFF61-\uFF9F/u)
  end

  def docs_sync_managed?
    properties.is_a?(Hash) && properties.dig("docs_sync", "source_path").present?
  end

  def docs_sync_read_only?
    docs_sync_managed? && properties.dig("docs_sync", "read_only") != false
  end

  def system_space_memo?
    memo_directory&.under_system_space?
  end

  private

  def clear_memo_group_when_not_group_visibility
    return if group_read? || group_read_write?

    self.memo_group_id = nil
  end

  def memo_group_must_include_owner
    return if memo_group_id.blank? || account_id.blank?
    return if MemoGroupMembership.exists?(memo_group_id: memo_group_id, account_id: account_id)

    errors.add(:memo_group_id, "はオーナーが参加しているグループを選んでください")
  end

  def kanban_placement_consistency
    if self[:board_id].blank?
      if self[:kanban_column_id].present?
        errors.add(:kanban_column_id, "はボード未所属のメモには設定できません")
      end
      return
    end

    if self[:kanban_column_id].blank?
      errors.add(:kanban_column_id, "を指定してください")
      return
    end

    return if kanban_column&.board_id == self[:board_id]

    errors.add(:kanban_column_id, "は同じボードの列を選んでください")
  end

  def memo_directory_must_be_assignable_location
    return if memo_directory.nil?
    return if memo_directory.directory_picker_selectable?(admin: account&.admin?)
    return if account&.admin? && memo_directory.under_system_space?

    if memo_directory.root?
      errors.add(:memo_directory, "ルートには保存できません")
    else
      errors.add(:memo_directory, "Home / Share / Public / System の直下には保存できません")
    end
  end

  # クライアント（オフライン）から渡された uid は正規化（大文字化）して尊重し、
  # 無ければサーバー側で ULID を採番する。冪等なので before_validation / before_create の双方から呼ぶ。
  def assign_uid
    normalized = uid.to_s.strip.upcase
    self.uid = normalized.presence || ::ULID.generate.to_s
  end

  def assign_default_memo_directory
    if memo_directory_id.blank? && account_id.present?
      self.memo_directory = MemoDirectory::UserSpace.default_home_directory(account_id)
    elsif memo_directory_id.blank?
      self.memo_directory = MemoDirectory.root
    end
  rescue ActiveRecord::RecordNotFound
    self.memo_directory = MemoDirectory.root if memo_directory_id.blank?
  end

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

  def prepare_slug_from_title_and_manual
    return if file_committed_at.present?

    # 空に戻したら自動同期モードへ
    self.slug_manual = false if slug.to_s.strip.blank?

    # 初回コミット前かつ自動モードでは常にタイトルから決める（クライアントの slug 単体 PATCH とサーバー側タイトルのずれで slug_manual が誤って true になるのを防ぐ）
    unless slug_manual?
      base = self.class.derived_slug_from_title(title, self)
      self.slug = base.presence
    end
  end

  def normalize_slug_for_storage
    frag = self.class.normalize_slug_fragment(slug)
    self.slug = frag
    return if slug.blank? || uid.blank?

    self.slug = self.class.global_slug_for(slug, uid)
  end

  def memo_wiki_links_need_outgoing_reindex?
    saved_change_to_body?
  end

  def memo_wiki_links_need_inbound_reindex?
    saved_change_to_title? || saved_change_to_slug? || saved_change_to_memo_directory_id?
  end

  def reindex_outgoing_wiki_links
    MemoWikiLinkIndex.rebuild_for(self)
  end

  def reindex_inbound_wiki_links
    MemoWikiLinkIndex.rebuild_inbound_for(self)
  end
end
