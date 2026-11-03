# frozen_string_literal: true

# Which "Sign in with …" buttons to show: a provider is enabled when its client id is set.
module OmniauthHelper
  CLIENT_ID_ENV = { google_oauth2: "GOOGLE_CLIENT_ID", discord: "DISCORD_CLIENT_ID" }.freeze

  def oauth_enabled?(provider)
    ENV[CLIENT_ID_ENV.fetch(provider.to_sym)].present?
  end
end
