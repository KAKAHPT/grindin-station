# frozen_string_literal: true

# Procs for number.nth: YAML cannot hold them. Mirrors the shape of the built-in :en entries.
{
  pt: {
    number: {
      nth: {
        ordinals: ->(_key, _options) { "º" },
        ordinalized: ->(_key, options) { "#{options[:number]}.º" }
      }
    }
  }
}
