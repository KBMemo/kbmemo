# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[style-src]

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.font_src :self, :data
    policy.form_action :self
    policy.frame_ancestors :self
    policy.img_src :self, :https, :data, :blob
    policy.object_src :none
    # Rails 8.1 exposes report-uri but not report-to in the CSP DSL.
    policy.directives["report-to"] = [ "csp" ]
    policy.report_uri "/csp_reports"
    policy.require_trusted_types_for :script
    policy.script_src :self
    policy.style_src :self
    policy.trusted_types(
      "default",
      "kbmemo-adoc-preview-html",
      "kbmemo-code-highlight-html",
      "kbmemo-sanitized-svg",
      "kbmemo-server-rendered-fragment"
    )

    if Rails.env.development?
      vite_origin = "http://#{ViteRuby.config.host_with_port}"
      policy.connect_src :self, vite_origin, "ws://#{ViteRuby.config.host_with_port}"
      policy.script_src *policy.script_src, vite_origin, :unsafe_eval
      policy.style_src *policy.style_src, :unsafe_inline
    end
  end

  # Existing pages still need discovery before enforcement. Keep this in report-only
  # while remaining inline/style sinks and third-party origins are audited.
  config.content_security_policy_report_only = true
end
