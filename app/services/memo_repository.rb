# frozen_string_literal: true

require "open3"
require "fileutils"

# メモの「コミット後の正」を Git 管理のファイルに書き出す。
# パス規則: {memo_directory_path_segment}/{slug_segment}-{memo_id}.adoc（ルートはファイル直下）
#
# DB はキャッシュ。ドラフトは DB のみ。「更新」で本クラス経由でファイル + git commit し、その後 DB 保存する想定。
class MemoRepository
  class Error < StandardError; end

  def initialize(root: nil)
    @root = Pathname.new(root || Rails.application.config.x.memo_git_work_tree)
  end

  attr_reader :root

  # メモの現在の属性（未保存の変更を含む）で相対パスを返す
  def relative_path_for(memo)
    filename = "#{filename_slug_segment(memo)}-#{memo.id}.adoc"
    return Pathname.new(filename) if memo.memo_directory.root?

    memo.memo_directory.repo_dirname.join(filename)
  end

  def absolute_path_for(memo)
    @root.join(relative_path_for(memo))
  end

  # YAML フロントマター + AsciiDoc 本文
  def file_contents_for(memo)
    meta = {
      "title" => memo.title.to_s,
      "tags" => memo.tags.map(&:name).sort,
      "properties" => memo.properties.is_a?(Hash) ? memo.properties.stringify_keys : memo.properties
    }
    yaml = meta.to_yaml
    yaml = yaml.sub(/\A---\s*\n?/, "")
    "---\n#{yaml.rstrip}\n---\n\n#{memo.body}"
  end

  # ディレクトリやファイル名変更時に作業ツリー上のファイルを移動（Git 追跡なら git mv）
  def relocate_file!(from_relative:, to_relative:)
    from_s = from_relative.to_s
    to_s = to_relative.to_s
    return if from_s == to_s

    full_from = @root.join(from_s)
    full_to = @root.join(to_s)
    return unless full_from.exist?

    full_to.parent.mkpath

    with_repo_lock do
      ensure_git_identity!
      tracked, = Open3.capture2("git", "ls-files", "--", from_s, chdir: @root.to_s)
      if tracked.to_s.strip.present?
        git!("mv", "--", from_s, to_s)
      else
        FileUtils.mv(full_from.to_s, full_to.to_s)
      end
    end
  end

  # ファイル書き込み + git add / commit（変更がない場合はコミットをスキップ）
  def write_and_commit!(memo, message: nil)
    ensure_repo!
    relative = relative_path_for(memo).to_s
    full = @root.join(relative)
    full.parent.mkpath

    content = file_contents_for(memo)
    File.write(full, content, encoding: "UTF-8")

    with_repo_lock do
      ensure_git_identity!
      git!("add", "--", relative)
      if git_index_dirty_for?(relative)
        msg = message || default_commit_message(memo)
        git!("commit", "-m", msg, "--", relative)
      end
    end
  end

  private

  def filename_slug_segment(memo)
    Memo.normalize_slug_fragment(memo.slug).presence || "memo"
  end

  def default_commit_message(memo)
    %(Update memo "#{memo.title.truncate(60)}" (#{memo.id}))
  end

  def ensure_repo!
    @root.mkpath
    return if @root.join(".git").exist?

    git!("init")
    ensure_git_identity!
  end

  def ensure_git_identity!
    email, = Open3.capture2("git", "config", "--get", "user.email", chdir: @root.to_s)
    name, = Open3.capture2("git", "config", "--get", "user.name", chdir: @root.to_s)
    return if email.to_s.strip.present? && name.to_s.strip.present?

    git!("config", "user.email", "kbmemo@localhost")
    git!("config", "user.name", "Kbmemo")
  end

  def with_repo_lock
    lock_path = @root.join(".kbmemo_git.lock")
    lock_path.parent.mkpath
    File.open(lock_path, File::CREAT | File::RDWR) do |f|
      f.flock(File::LOCK_EX)
      yield
    ensure
      f.flock(File::LOCK_UN)
    end
  end

  def git_index_dirty_for?(relative_path)
    out, err, st = Open3.capture3("git", "diff", "--cached", "--name-only", "--", relative_path, chdir: @root.to_s)
    raise Error, (err.presence || out).to_s.strip unless st.success?

    out.strip.present?
  end

  def git!(*args)
    cmd = [ "git", *args.map(&:to_s) ]
    out, err, st = Open3.capture3(*cmd, chdir: @root.to_s)
    raise Error, (err.presence || out).to_s.strip unless st.success?

    [ out, err ]
  end
end
