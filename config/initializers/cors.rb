# frozen_string_literal: true

# The stream kit (OBS browser sources, any origin) reads the public feeds; nothing else is cross-origin.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"
    resource "/api/v1/*", headers: :any, methods: %i[get head]
  end
end
