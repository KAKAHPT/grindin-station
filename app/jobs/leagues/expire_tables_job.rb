# frozen_string_literal: true

module Leagues
  # Closes the waiting tables that did not fill in time. Runs every minute (config/recurring.yml).
  class ExpireTablesJob < ApplicationJob
    def perform = Tables::Expire.call
  end
end
