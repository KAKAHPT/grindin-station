# frozen_string_literal: true

# Permissions-Policy header (the standard name; Rails' permissions_policy DSL still writes the legacy
# Feature-Policy): the app uses no device features, fullscreen is for the round timer only.
Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] =
  "camera=(), microphone=(), geolocation=(), usb=(), payment=(), fullscreen=(self)"
