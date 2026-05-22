# frozen_string_literal: true

require "open3"

class PandocRunner
  class Error < StandardError; end
  class NotFound < Error; end

  class << self
    def convert(from:, to:, input:, extra_args: [])
      path = pandoc_path
      raise NotFound, "pandoc が見つかりません。PATH に pandoc を追加するか PANDOC_PATH を設定してください。" unless path

      stdout, stderr, status = Open3.capture3(
        path,
        "-f", from,
        "-t", to,
        *Array(extra_args),
        "-",
        stdin_data: input.to_s
      )
      raise Error, stderr.presence || "pandoc の変換に失敗しました。" unless status.success?

      stdout
    end

    def pandoc_path
      @pandoc_path = nil if defined?(@@reset_pandoc_path) && @@reset_pandoc_path
      @pandoc_path ||= locate_pandoc
    end

    def reset_pandoc_path!
      @pandoc_path = nil
    end

    private

    def locate_pandoc
      candidate = ENV["PANDOC_PATH"].presence || ENV["PANDOC"].presence
      return candidate if candidate.present? && File.executable?(candidate)

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, "pandoc")
        return path if File.executable?(path)
      end

      nil
    end
  end
end
