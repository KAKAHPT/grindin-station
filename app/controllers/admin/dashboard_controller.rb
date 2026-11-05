# frozen_string_literal: true

module Admin
  class DashboardController < BaseController
    def show
      @overview = Overview.call
    end
  end
end
