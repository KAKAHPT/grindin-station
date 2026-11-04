# frozen_string_literal: true

module Api
  module V1
    # Public, unauthenticated JSON for the stream kit: cached 30 s by anyone, validated by the event's
    # latest change. Draft and canceled events are not found, whoever asks.
    class BaseController < ApplicationController
      skip_before_action :require_authentication
      skip_forgery_protection
      before_action :set_cache

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end

      private

      def set_cache
        expires_in 30.seconds, public: true
      end

      def find_feed_event!
        event = Tournament.find_by!(slug: params.expect(:slug))
        raise ActiveRecord::RecordNotFound if event.state.in?(PublicEvent::HIDDEN_STATES)

        event
      end

      def render_feed(feed)
        event = find_feed_event!
        updated = Feeds.last_change(event)
        return unless stale?(etag: [action_name, event.id, event.rounds_count, updated], last_modified: updated,
                             public: true)

        render json: feed.call(event, updated: updated)
      end
    end
  end
end
