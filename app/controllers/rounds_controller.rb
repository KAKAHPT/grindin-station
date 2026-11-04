# frozen_string_literal: true

class RoundsController < ApplicationController
  include PublicEvent

  skip_before_action :require_authentication, only: :show

  def show
    event = load_event
    @round = load_round(event)
    @pods = load_pods(@round)
    @users_map = load_users_map(@pods)

    return if params[:query].blank?

    @users_map.filter! { |_, v| v[:name].downcase.include?(params[:query].downcase) }
  end

  private

  def load_event
    ensure_public!(Tournament.find(params[:tournament_id]))
  end

  def load_round(event)
    event.rounds.published.find params[:id]
  end

  def load_pods(round)
    round.pods.preload({ round: :results }, seatings: { event_participant: { player: :user } },
                                            event_participants: { player: :user })
  end

  def load_users_map(pods)
    users_map = {}
    pods.each do |p|
      p.seatings.each do |s|
        users_map[s.event_participant_id] = {
          tp: s.event_participant,
          name: s.event_participant.name,
          pod: "Pod #{p.number}",
          seating: s.order.ordinalize
        }
      end
    end
    users_map
  end
end
