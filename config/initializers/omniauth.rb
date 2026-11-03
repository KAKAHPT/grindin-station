# frozen_string_literal: true

# Sign in with Google / Discord. Without the env vars the providers stay configured with nil keys
# and the sign-in page hides their buttons (OmniauthHelper#oauth_enabled?).
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch("GOOGLE_CLIENT_ID", nil), ENV.fetch("GOOGLE_CLIENT_SECRET", nil)
  provider :discord, ENV.fetch("DISCORD_CLIENT_ID", nil), ENV.fetch("DISCORD_CLIENT_SECRET", nil),
           scope: "identify email"
end

OmniAuth.config.allowed_request_methods = [:post]
OmniAuth.config.logger = Rails.logger
