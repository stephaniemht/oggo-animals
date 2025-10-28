Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.style_src   :self, "https://fonts.googleapis.com", :unsafe_inline
    policy.font_src    :self, "https://fonts.gstatic.com", :data
    policy.img_src     :self, :data, :blob

    # ✅ CSP stricte pour les <script> avec nonce généré par Rails
    policy.script_src :self, :https, :unsafe_inline

    policy.connect_src :self
  end

  # On applique vraiment (pas en report-only)
  config.content_security_policy_report_only = false
end




# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# Rails.application.configure do
#   config.content_security_policy do |policy|
#     policy.default_src :self, :https
#     policy.font_src    :self, :https, :data
#     policy.img_src     :self, :https, :data
#     policy.object_src  :none
#     policy.script_src  :self, :https
#     policy.style_src   :self, :https
#     # Specify URI for violation reports
#     # policy.report_uri "/csp-violation-report-endpoint"
#   end
#
#   # Generate session nonces for permitted importmap, inline scripts, and inline styles.
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
#   config.content_security_policy_nonce_directives = %w(script-src style-src)
#
#   # Report violations without enforcing the policy.
#   # config.content_security_policy_report_only = true
# end
