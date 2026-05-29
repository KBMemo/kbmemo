# frozen_string_literal: true

require "open3"

# Git 作業ツリー上のメモ .adoc / .assets を、レガシー *-{id} から uid サフィックスへ揃える。
# DB の slug 移行（MigrateMemoSlugSuffixesToUid）後に実行する想定。
class MemoSlugGitRename
  class Error < StandardError; end

  Result = Data.define(
    :memo_id,
    :uid,
    :from_adoc,
    :to_adoc,
    :from_assets,
    :to_assets,
    :status,
    :message
  )

  def initialize(repo: MemoRepository.new, dry_run: true, git_commit: false)
    @repo = repo
    @dry_run = dry_run
    @git_commit = git_commit && !dry_run
  end

  # @return [Array<Result>]
  def call
    ensure_git_repo!

    results = Memo.find_each.map { |memo| process_memo(memo) }
    commit_renames!(results) if @git_commit && results.any? { |r| r.status == :renamed }
    results
  end

  def summary_lines(results)
    counts = results.group_by(&:status).transform_values(&:size)
    lines = [
      "memo slug git rename#{@dry_run ? " (dry run)" : ""}",
      "  repo: #{@repo.root}",
      "  renamed: #{counts[:renamed] || 0}",
      "  dry_run: #{counts[:dry_run] || 0}",
      "  skipped: #{counts[:skipped] || 0}",
      "  errors: #{counts[:error] || 0}"
    ]

    results.select { |r| r.status == :error }.each do |r|
      lines << "  ERROR memo #{r.memo_id}: #{r.message}"
    end

    actionable = results.select { |r| r.status.in?(%i[dry_run renamed]) }
    if actionable.any?
      lines << "  paths:"
      actionable.each do |r|
        lines << "    memo #{r.memo_id}: #{r.from_adoc} -> #{r.to_adoc}"
        lines << "      assets: #{r.from_assets} -> #{r.to_assets}" if r.from_assets.present?
      end
    end

    lines
  end

  private

  def ensure_git_repo!
    return if @repo.root.join(".git").directory?

    raise Error, "Git repository not found at #{@repo.root}"
  end

  def process_memo(memo)
    target_adoc = @repo.relative_path_for(memo).to_s
    legacy_adoc = find_legacy_adoc_path(memo)

    unless legacy_adoc
      if path_exists_in_repo?(target_adoc)
        return result_for(
          memo,
          status: :skipped,
          message: "already at uid path",
          from_adoc: target_adoc,
          to_adoc: target_adoc
        )
      end

      return result_for(
        memo,
        status: :skipped,
        message: "no *-#{memo.id}.adoc in work tree or git index"
      )
    end

    if legacy_adoc == target_adoc
      return result_for(
        memo,
        status: :skipped,
        message: "legacy path already matches target",
        from_adoc: legacy_adoc,
        to_adoc: target_adoc
      )
    end

    if path_exists_in_repo?(target_adoc) && legacy_adoc != target_adoc
      return result_for(
        memo,
        status: :error,
        message: "target already exists: #{target_adoc}",
        from_adoc: legacy_adoc,
        to_adoc: target_adoc
      )
    end

    legacy_assets = assets_dir_for(legacy_adoc)
    target_assets = assets_dir_for(target_adoc)
    legacy_assets_exist = @repo.root.join(legacy_assets).directory?

    entry = result_for(
      memo,
      status: @dry_run ? :dry_run : :renamed,
      from_adoc: legacy_adoc,
      to_adoc: target_adoc,
      from_assets: legacy_assets_exist ? legacy_assets : nil,
      to_assets: legacy_assets_exist ? target_assets : nil
    )

    return entry if @dry_run

    @repo.relocate_path!(from_relative: legacy_adoc, to_relative: target_adoc)
    if legacy_assets_exist
      @repo.relocate_path!(from_relative: legacy_assets, to_relative: target_assets)
    end

    entry
  end

  def result_for(memo, status:, message: nil, from_adoc: nil, to_adoc: nil, from_assets: nil, to_assets: nil)
    Result.new(
      memo.id,
      memo.uid,
      from_adoc,
      to_adoc,
      from_assets,
      to_assets,
      status,
      message
    )
  end

  def find_legacy_adoc_path(memo)
    suffix = "-#{memo.id}.adoc"
    candidates = (git_tracked_paths + work_tree_paths(suffix)).uniq
    candidates.select! { |path| path.end_with?(suffix) }
    return nil if candidates.empty?
    return candidates.first if candidates.size == 1

    candidates.max_by { |path| last_commit_epoch_for_path(path) }
  end

  def assets_dir_for(adoc_relative)
    path = Pathname.new(adoc_relative)
    path.dirname.join("#{path.basename('.adoc')}.assets").to_s
  end

  def git_tracked_paths
    out, err, st = Open3.capture3("git", "ls-files", chdir: @repo.root.to_s)
    raise Error, err.to_s.strip unless st.success?

    out.each_line.map(&:strip).reject(&:blank?)
  end

  def work_tree_paths(suffix)
    @repo.root.glob("**/*#{suffix}").map { |abs| abs.relative_path_from(@repo.root).to_s }
  end

  def path_exists_in_repo?(relative_path)
    rel = relative_path.to_s
    return false if rel.blank?

    @repo.root.join(rel).exist? || git_tracked_paths.include?(rel)
  end

  def last_commit_epoch_for_path(relative_path)
    rel = relative_path.to_s
    out, _err, st = Open3.capture3("git", "log", "-1", "--format=%ct", "--", rel, chdir: @repo.root.to_s)
    return 0 unless st.success?

    out.to_s.strip.to_i
  end

  def commit_renames!(results)
    with_repo_lock do
      ensure_git_identity!
      dirty, err, st = Open3.capture3("git", "diff", "--cached", "--quiet", chdir: @repo.root.to_s)
      raise Error, err.to_s.strip unless st.success? || st.exitstatus == 1
      return if st.exitstatus.zero?

      git!("commit", "-m", "Rename memo work tree files to uid-based slugs")
    end
  end

  def ensure_git_identity!
    email, = Open3.capture2("git", "config", "--get", "user.email", chdir: @repo.root.to_s)
    name, = Open3.capture2("git", "config", "--get", "user.name", chdir: @repo.root.to_s)
    return if email.to_s.strip.present? && name.to_s.strip.present?

    git!("config", "user.email", "kbmemo@localhost")
    git!("config", "user.name", "Kbmemo")
  end

  def with_repo_lock
    lock_path = @repo.root.join(".kbmemo_git.lock")
    lock_path.parent.mkpath
    File.open(lock_path, File::CREAT | File::RDWR) do |f|
      f.flock(File::LOCK_EX)
      yield
    ensure
      f.flock(File::LOCK_UN)
    end
  end

  def git!(*args)
    _out, err, st = Open3.capture3("git", *args.map(&:to_s), chdir: @repo.root.to_s)
    raise Error, err.to_s.strip unless st.success?
  end
end
