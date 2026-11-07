# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  # Modal-style pages render inside the modal frame when requested by it, else as a full page.
  layout -> { turbo_frame_request_id == "modal" ? "modal" : "modal_page" }, only: %i[new edit]

  before_action :set_request_context
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

  # The request path for error and audit records, with a bearer token in it (the password reset link) hidden.
  def self.redacted_path(request)
    token = request.path_parameters[:token].to_s
    token.empty? ? request.path : request.path.sub(token, "[FILTERED]")
  end

  private

  def set_request_context
    Current.ip_address = request.remote_ip
    Current.request_id = request.request_id
    Current.request_path = self.class.redacted_path(request)
  end

  # Locale: ?locale= (which is also remembered), else the locale cookie, else the browser's Accept-Language,
  # else the default.
  # TODO(user locale): the user's saved preference (users.locale) takes priority here once the column exists.
  def switch_locale(&block)
    locale = available_locale(params[:locale])
    if locale
      remember_locale(locale)
    else
      locale = available_locale(cookies[:locale]) || header_locale || I18n.default_locale
    end
    I18n.with_locale(locale, &block)
  end

  def remember_locale(locale)
    return if cookies[:locale] == locale.to_s

    cookies[:locale] = { value: locale.to_s, expires: 1.year, httponly: true, same_site: :lax }
  end

  def available_locale(value)
    I18n.available_locales.find { |locale| locale.to_s == value.to_s }
  end

  # The first available language of Accept-Language, in the order the browser lists them (by preference):
  # "fr-FR,pt;q=0.9,en;q=0.8" -> :pt.
  def header_locale
    request.headers["Accept-Language"].to_s.split(",").each do |entry|
      locale = available_locale(entry.split(";").first.to_s.strip.split("-").first.to_s.downcase)
      return locale if locale
    end
    nil
  end
end
