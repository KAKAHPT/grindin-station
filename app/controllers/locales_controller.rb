# frozen_string_literal: true

# The top bar's language switch: remembers the chosen locale in the cookie and goes back to the same page.
class LocalesController < ApplicationController
  allow_unauthenticated_access

  def update
    locale = available_locale(params[:locale])
    remember_locale(locale) if locale
    redirect_to page_back, status: :see_other
  end

  private

  # The referring page on this host, minus its ?locale= (which would override the new choice).
  def page_back
    back = url_from(request.referer)
    return root_path unless back

    uri = URI.parse(back)
    uri.query = Rack::Utils.parse_nested_query(uri.query.to_s).except("locale").to_query.presence
    uri.to_s
  rescue URI::InvalidURIError
    root_path
  end
end
