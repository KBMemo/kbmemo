# frozen_string_literal: true

class MemoDirectory
  # ルート直下の system バケットと system/docs・system/help を管理する。
  class SystemSpace
    ROOT = "system"
    DOCS = "docs"
    HELP = "help"
    FIXED_CHILDREN = { DOCS => "Docs", HELP => "Help" }.freeze

    class << self
      def ensure_buckets!
        root = MemoDirectory.root
        system = ensure_segment!(root, ROOT, "System")
        FIXED_CHILDREN.each do |seg, label|
          ensure_segment!(system, seg, label)
        end
      end

      # `system/docs/...` または `system/help/...` の segments から末端ディレクトリを返す。
      def ensure_subdirectory!(*segments)
        ensure_buckets!
        segments = Array(segments).flatten.compact_blank.map(&:to_s)
        raise ArgumentError, "segments required" if segments.empty?

        parent = MemoDirectory.find_by!(full_path: ROOT)
        segments.each do |seg|
          fp = "#{parent.full_path}/#{seg}"
          parent = MemoDirectory.find_by(full_path: fp) ||
            MemoDirectory.create!(parent: parent, path_segment: seg, label: seg.tr("-", " ").humanize)
        end
        parent
      end

      def docs_directory
        ensure_buckets!
        MemoDirectory.find_by!(full_path: "#{ROOT}/#{DOCS}")
      end

      def help_directory
        ensure_buckets!
        MemoDirectory.find_by!(full_path: "#{ROOT}/#{HELP}")
      end

      private

      def ensure_segment!(parent, seg, label)
        fp = parent.root? ? seg : "#{parent.full_path}/#{seg}"
        MemoDirectory.find_by(full_path: fp) ||
          MemoDirectory.create!(parent: parent, path_segment: seg, label: label)
      end
    end
  end
end
