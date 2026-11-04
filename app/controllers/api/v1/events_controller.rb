# frozen_string_literal: true

module Api
  module V1
    # /api/v1/events/:slug/{standings,rounds,info}: see Feeds.
    class EventsController < BaseController
      def standings = render_feed(Feeds::Standings)
      def rounds = render_feed(Feeds::Rounds)
      def info = render_feed(Feeds::Info)
    end
  end
end
