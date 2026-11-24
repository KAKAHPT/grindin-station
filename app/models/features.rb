# frozen_string_literal: true

# The modules that can be paused (config/features.yml): `Features.on?(:feed)` in views and controllers,
# `constraints(Features.constraint(:feed))` around a module's routes, so its addresses are not found while it is off.
module Features
  NAMES = %i[feed leagues circuits rankings teams one_v_one fairness organizers].freeze

  class << self
    # Tests assign a set (Features.launch) and nil to go back to the file.
    attr_writer :settings

    # An unknown name raises, so a typo cannot read as "off".
    def on?(name) = settings.fetch(name)

    def settings = @settings ||= read(Rails.env)

    # What production runs with.
    def launch = read("production")

    def constraint(name) = ->(_request) { on?(name) }

    private

    def read(env) = Rails.application.config_for(:features, env: env).to_h.slice(*NAMES)
  end
end
