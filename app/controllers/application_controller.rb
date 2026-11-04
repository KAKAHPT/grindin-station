# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  # Modal-style pages render inside the modal frame when requested by it, else as a full page.
  layout -> { turbo_frame_request_id == "modal" ? "modal" : "modal_page" }, only: %i[new edit]

  around_action :switch_locale

  unless Rails.env.production?
    around_action :n_plus_one_detection

    def n_plus_one_detection
      Prosopite.scan
      yield
    ensure
      Prosopite.finish
    end
  end

  private

  # TODO(user locale): the user's saved preference (users.locale) takes priority here once the column exists.
  def switch_locale(&block)
    requested = params[:locale].to_s.to_sym
    locale = I18n.available_locales.include?(requested) ? requested : I18n.default_locale
    I18n.with_locale(locale, &block)
  end
end
