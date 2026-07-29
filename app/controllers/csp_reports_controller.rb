require "json"
require "uri"

class CspReportsController < ActionController::API
  MAX_REPORT_BYTES = 64.kilobytes
  LOG_KEYS = %w[
    blocked_uri
    disposition
    document_uri
    effective_directive
    line_number
    original_policy
    referrer
    source_file
    status_code
    violated_directive
    column_number
  ].freeze
  URI_KEYS = %w[blocked_uri document_uri referrer source_file].freeze

  def create
    reports = parse_reports(request.raw_post.to_s.byteslice(0, MAX_REPORT_BYTES))
    reports.each { |report| log_report(report) }
    head :no_content
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def parse_reports(raw_body)
    payload = JSON.parse(raw_body.presence || "{}")
    Array.wrap(payload).filter_map do |entry|
      normalized_report(entry)
    end
  end

  def normalized_report(entry)
    return entry["csp-report"] if entry.is_a?(Hash) && entry["csp-report"].is_a?(Hash)
    return entry["body"] if entry.is_a?(Hash) && entry["type"] == "csp-violation" && entry["body"].is_a?(Hash)
    return entry if entry.is_a?(Hash)

    nil
  end

  def log_report(report)
    safe_report = LOG_KEYS.each_with_object({}) do |key, acc|
      value = report_value(report, key)
      next if value.blank?

      acc[key] = URI_KEYS.include?(key) ? scrub_uri(value) : value.to_s.first(240)
    end
    Rails.logger.info({ event: "csp_violation_report", report: safe_report }.to_json)
  end

  def report_value(report, key)
    report[key] || report[key.tr("_", "-")] || report[key.camelize(:lower)]
  end

  def scrub_uri(value)
    uri = URI.parse(value.to_s)
    uri.query = nil if uri.respond_to?(:query=)
    uri.fragment = nil if uri.respond_to?(:fragment=)
    uri.to_s.first(240)
  rescue URI::InvalidURIError
    "[invalid-uri]"
  end
end
