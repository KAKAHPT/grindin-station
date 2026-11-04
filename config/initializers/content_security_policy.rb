# frozen_string_literal: true

# Content security policy, in report-only mode: browsers log violations to the console but block nothing.
# To enforce it, set content_security_policy_report_only to false once a few event days show no violations.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

# The phone layouts swap the web-font stylesheet in with onload="this.media='all'" (_phone_head).
FONT_SWAP_HANDLER_HASH = "'sha256-MhtPZXr7+LpJUY5qtMutB+qWfQtMaPccfe7QXtCcEYc='"

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self, :unsafe_hashes, FONT_SWAP_HANDLER_HASH
    # Tailwind and Turbo set inline styles; Google Fonts and the Leaflet stylesheet are external.
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com", "https://cdn.jsdelivr.net"
    policy.img_src :self, :data, :blob, :https
    policy.font_src :self, :data, "https://fonts.gstatic.com"
    # 'self' covers the Action Cable websocket on the same host.
    policy.connect_src :self
    policy.object_src :none
    policy.frame_ancestors :none
    # Violations are logged by CspReportsController.
    policy.report_uri "/csp-reports"
  end

  # A fresh nonce per response for the importmap and module scripts; Turbo ignores the nonce when it
  # compares tracked head elements. Not style-src: a nonce there would switch off unsafe-inline.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  config.content_security_policy_report_only = true
end
