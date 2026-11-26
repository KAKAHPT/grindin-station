# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/admin/summary: the site's growth for the operator's desktop assistant (JARVIS), see Admin::Summary.
    # Private: a bearer token compared with ENV["JARVIS_API_TOKEN"]. Without that variable (or with one shorter than
    # MIN_TOKEN) the address is not found for anyone; a missing or wrong token is 401. No session, cookie or CSRF,
    # never cached, 30 requests a minute per address. Not under BaseController, whose feeds are public and cached.
    class AdminSummaryController < ApplicationController
      MIN_TOKEN = 32

      skip_before_action :require_authentication
      skip_forgery_protection
      skip_around_action :switch_locale
      rate_limit to: 30, within: 1.minute, by: -> { request.remote_ip },
                 with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }
      before_action :no_store
      before_action :authenticate_token!

      def show
        render json: ::Admin::Summary.call
      end

      private

      def no_store
        response.headers["Cache-Control"] = "no-store"
      end

      def authenticate_token!
        expected = ENV["JARVIS_API_TOKEN"].to_s.strip
        return render(json: { error: "not_found" }, status: :not_found) if expected.length < MIN_TOKEN

        given = request.authorization.to_s[/\ABearer (\S+)\z/, 1].to_s
        return if ActiveSupport::SecurityUtils.secure_compare(given, expected)

        render json: { error: "unauthorized" }, status: :unauthorized
      end
    end
  end
end
